// ============================================================
//  screens/encrypted_chat_screen.dart
//  Phase 4: Encrypted One-Time Chat
//
//  SECURITY:
//  - Uses the in-memory AES-256-GCM shared key.
//  - Messages are decrypted on the fly as they arrive from Firestore.
//  - Plaintext is NEVER stored anywhere.
//  - Leaving the chat immediately wipes all messages and keys.
//
//  REAL-TIME END-SESSION:
//  - A single Firestore listener on sessions/{sessionId} watches status.
//  - When status becomes "ended" or "expired" (from either user),
//    _navigateHome() is called exactly once on BOTH devices.
//  - The user who pressed End Session sees "messages deleted" snackbar.
//  - The other user sees "ended by the other user" snackbar.
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/message_model.dart';
import '../models/session_model.dart';
import '../services/session_service.dart';
import 'home_screen.dart';

class EncryptedChatScreen extends StatefulWidget {
  final SessionModel session;
  final List<int> sharedKeyBytes;

  const EncryptedChatScreen({
    super.key,
    required this.session,
    required this.sharedKeyBytes,
  });

  @override
  State<EncryptedChatScreen> createState() => _EncryptedChatScreenState();
}

class _EncryptedChatScreenState extends State<EncryptedChatScreen> {
  final _sessionService = SessionService();
  final _messageController = TextEditingController();
  final _currentUser = FirebaseAuth.instance.currentUser!;

  // ── State flags ──────────────────────────────────────────────

  /// True once the current user has initiated End Session.
  /// Used to suppress the "ended by other user" message for the initiator.
  bool _isEndingSession = false;

  /// True once navigation to HomeScreen has been triggered.
  /// Acts as a single-fire gate — prevents any duplicate navigation
  /// from multiple Firestore snapshot events or concurrent calls.
  bool _hasNavigatedAfterEnd = false;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSub;

  // ── Lifecycle ────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _startSessionListener();
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _messageController.dispose();
    // Best-effort: zero out the in-memory key.
    _wipeKey();
    super.dispose();
  }

  // ── Key helpers ──────────────────────────────────────────────

  void _wipeKey() {
  try {
    for (int i = 0; i < widget.sharedKeyBytes.length; i++) {
      widget.sharedKeyBytes[i] = 0;
    }
    debugPrint('Safe Debug: Shared key wiped from memory');
  } catch (e) {
    debugPrint(
      'Safe Debug: Shared key wipe skipped because bytes are unmodifiable',
    );
  }
}

  // ── Safe navigation ──────────────────────────────────────────

  /// Navigate both users to HomeScreen.
  /// [showOtherUserMessage] — true if this device is the *receiving* side.
  void _navigateHome({required bool showOtherUserMessage}) {
    if (!mounted || _hasNavigatedAfterEnd) return;

    // Cancel listener and wipe key immediately
    _sessionSub?.cancel();
    _wipeKey();

    if (showOtherUserMessage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Secure session ended by the other user.'),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Secure session ended and messages deleted.'),
          backgroundColor: Color(0xFF00D4AA),
          duration: Duration(seconds: 3),
        ),
      );
    }

    _hasNavigatedAfterEnd = true;
    debugPrint('Safe Debug: Navigating to HomeScreen now');

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );

    debugPrint('Safe Debug: Navigation command sent');
  }

  // ── Firestore session listener ───────────────────────────────

  /// Starts a real-time listener on the session document.
  /// Both users run this listener for the entire chat duration.
  /// When status becomes "ended" or "expired", _navigateHome() fires.
  void _startSessionListener() {
    _sessionSub = FirebaseFirestore.instance
        .collection('sessions')
        .doc(widget.session.sessionId)
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        if (!snap.exists) return;

        final data = snap.data();
        if (data == null) return;

        final status = data['status'] as String?;
        debugPrint('Safe Debug: Session status changed: $status');

        if (status == 'ended' || status == 'expired') {
          if (_hasNavigatedAfterEnd) return;

          // If _isEndingSession is true, THIS device initiated the end —
          // _navigateHome was already called inside _endSession().
          // The listener arriving here is a no-op for the initiator.
          if (_isEndingSession) return;

          // This device is the RECEIVING side — the other user ended it.
          debugPrint('Safe Debug: Remote session end detected');
          _navigateHome(showOtherUserMessage: true);
        }
      },
      onError: (e) {
        debugPrint('Safe Debug: Session listener error: $e');
      },
    );
  }

  // ── Messaging ────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    if (_isEndingSession || _hasNavigatedAfterEnd) return;
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    try {
      await _sessionService.sendMessage(
        sessionId: widget.session.sessionId,
        sharedKeyBytes: widget.sharedKeyBytes,
        text: text,
        senderUid: _currentUser.uid,
        senderEmail: _currentUser.email ?? '',
        senderDisplayName: _currentUser.displayName,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ── End Session (current user initiates) ─────────────────────

  Future<void> _endSession() async {
    if (_hasNavigatedAfterEnd) return;

    // Mark as ending BEFORE any await so the listener treats this
    // device's own snapshot as "self-initiated" and doesn't double-navigate.
    _isEndingSession = true;

    debugPrint('Safe Debug: Updating session status to ended');

    try {
      // Step 1: Update session document status first.
      // This triggers the other user's listener immediately.
      await _sessionService.endChatSession(
        widget.session.sessionId,
        endedByUid: _currentUser.uid,
        endedByEmail: _currentUser.email,
      );
    } catch (e) {
      debugPrint('Safe Debug: endChatSession error (ignored): $e');
      // Even if write fails, still navigate home to avoid being stuck.
    } finally {
      debugPrint('Safe Debug: Session ended, navigating home');

      // Navigate the initiating user home.
      // showOtherUserMessage = false → shows "messages deleted" snackbar.
      _navigateHome(showOtherUserMessage: false);
    }
  }

  Future<void> _attemptEndSession() async {
    if (_hasNavigatedAfterEnd || _isEndingSession) return;

    final shouldEnd = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141824),
        title: const Text(
          'End Session?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Leaving this screen will end the one-time secure session and '
          'permanently delete all encrypted messages. Proceed?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'End Session',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (shouldEnd == true) {
      await _endSession();
    }
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _attemptEndSession();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0E1A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF141824),
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Secure Chat',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                'Session: ${widget.session.sessionId.substring(0, 8)}...',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              ),
            ],
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: _attemptEndSession,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.exit_to_app_rounded,
                  color: Colors.redAccent),
              tooltip: 'End Session',
              onPressed: _attemptEndSession,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Security label
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                color: const Color(0xFF00D4AA).withValues(alpha: 0.1),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_rounded,
                        size: 14, color: Color(0xFF00D4AA)),
                    SizedBox(width: 6),
                    Text(
                      'End-to-end encrypted \u2022 One-time session',
                      style: TextStyle(
                        color: Color(0xFF00D4AA),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              // Message list
              Expanded(
                child: StreamBuilder<List<MessageModel>>(
                  stream: _sessionService.watchMessages(
                      widget.session.sessionId, widget.sharedKeyBytes),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Center(
                        child: Text(
                          'Error loading messages',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF00D4AA)),
                      );
                    }

                    final messages = snapshot.data!;
                    if (messages.isEmpty) {
                      return Center(
                        child: Text(
                          'No messages yet.\nStart the conversation!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      );
                    }

                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isMe = msg.senderUid == _currentUser.uid;
                        return _MessageBubble(message: msg, isMe: isMe);
                      },
                    );
                  },
                ),
              ),

              // Input area — hidden once ending session
              if (_isEndingSession || _hasNavigatedAfterEnd)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: LinearProgressIndicator(color: Colors.redAccent),
                )
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  color: const Color(0xFF141824),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Type an encrypted message...',
                            hintStyle:
                                TextStyle(color: Colors.grey.shade600),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: const Color(0xFF1E2130),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF00D4AA),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.send_rounded,
                              color: Color(0xFF0A0E1A)),
                          onPressed: _sendMessage,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Message Bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;

  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final hasError =
        message.decryptedText == '[Unable to decrypt message]';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isMe
                    ? 'You'
                    : (message.senderDisplayName ?? message.senderEmail),
                style:
                    TextStyle(fontSize: 10, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: hasError
                  ? Colors.redAccent.withValues(alpha: 0.2)
                  : isMe
                      ? const Color(0xFF00D4AA).withValues(alpha: 0.15)
                      : const Color(0xFF252A3A),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMe ? 16 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 16),
              ),
              border: Border.all(
                color: hasError
                    ? Colors.redAccent.withValues(alpha: 0.5)
                    : isMe
                        ? const Color(0xFF00D4AA).withValues(alpha: 0.3)
                        : Colors.transparent,
              ),
            ),
            child: Text(
              message.decryptedText ?? '...',
              style: TextStyle(
                color: hasError ? Colors.redAccent : Colors.white,
                fontSize: 15,
                fontStyle:
                    hasError ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
