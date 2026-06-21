// ============================================================
//  screens/create_session_screen.dart
//  Host flow:
//    1. On mount: generate ephemeral X25519 key pair + session doc.
//    2. Show QR code + selectable JSON payload.
//    3. Countdown timer (10 min). Expire on timeout.
//    4. Stream Firestore → when participant joins, derive shared key
//       locally and navigate to SessionEstablishedScreen.
//
//  SECURITY: hostKeyPair (SimpleKeyPair) never leaves this widget's
//  state. It is discarded when the widget is disposed or after the
//  shared key has been derived.
// ============================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cryptography/cryptography.dart';
import '../models/session_model.dart';
import '../services/session_service.dart';
import 'session_established_screen.dart';

class CreateSessionScreen extends StatefulWidget {
  const CreateSessionScreen({super.key});

  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  final _sessionService = SessionService();

  // ── State ────────────────────────────────────────────────────
  bool _loading = true;
  String? _error;

  SessionModel? _session;

  /// Host's ephemeral X25519 key pair — kept only in memory.
  /// Used to derive the shared key once the participant joins.
  SimpleKeyPair? _hostKeyPair;

  String? _qrPayload;

  // Countdown (600 s = 10 min)
  Timer? _countdownTimer;
  int _secondsLeft = 600;

  // Firestore stream subscription
  StreamSubscription<SessionModel?>? _sessionSub;

  bool _expired = false;
  bool _navigated = false; // prevent double-navigation

  // ── Lifecycle ────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _sessionSub?.cancel();
    // hostKeyPair is a Dart object; GC will clean it up.
    super.dispose();
  }

  // ── Initialisation ───────────────────────────────────────────

  Future<void> _initSession() async {
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final (session, keyPair) = await _sessionService.createSession(
        createdByUid: user.uid,
        createdByEmail: user.email ?? '',
      );

      _session = session;
      _hostKeyPair = keyPair; // private key kept in memory only
      _qrPayload = _sessionService.buildQrPayload(session);

      if (!mounted) return;
      setState(() => _loading = false);

      _startCountdown();
      _watchForParticipant();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to create session: $e';
      });
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) {
          t.cancel();
          _expired = true;
          _sessionSub?.cancel();
          _sessionService.endSession(_session!.sessionId);
        }
      });
    });
  }

  void _watchForParticipant() {
    _sessionSub =
        _sessionService.watchSession(_session!.sessionId).listen((updated) async {
      if (_navigated || !mounted) return;

      if (updated == null || updated.isEnded) {
        // Session was ended externally
        if (mounted) {
          setState(() => _expired = true);
          _countdownTimer?.cancel();
        }
        return;
      }

      // Participant has joined — derive shared key locally
      if (updated.isActive && updated.joinedByPublicKey != null) {
        _navigated = true;
        _countdownTimer?.cancel();
        _sessionSub?.cancel();

        try {
          final sharedKey = await _sessionService.deriveSharedKey(
            myKeyPair: _hostKeyPair!,
            theirPublicKeyHex: updated.joinedByPublicKey!,
            sessionId: updated.sessionId,
          );

          // _hostKeyPair no longer needed — discard reference
          _hostKeyPair = null;

          if (!mounted) return;
          Navigator.of(context).pushReplacement(PageRouteBuilder(
            pageBuilder: (_, __, ___) => SessionEstablishedScreen(
              session: updated,
              sharedKeyBytes: sharedKey,
              isHost: true,
            ),
            transitionDuration: const Duration(milliseconds: 350),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ));
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Key derivation failed: $e'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        }
      }
    });
  }

  // ── Helpers ──────────────────────────────────────────────────

  String get _timeLabel {
    final m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Color get _timerColor {
    if (_secondsLeft > 300) return const Color(0xFF00D4AA);
    if (_secondsLeft > 60) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  void _copyPayload() {
    if (_qrPayload == null) return;
    Clipboard.setData(ClipboardData(text: _qrPayload!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Payload copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded,
              color: Colors.white70, size: 22),
          onPressed: () async {
            if (_session != null) {
              await _sessionService.endSession(_session!.sessionId);
            }
            if (mounted) Navigator.of(context).pop();
          },
        ),
        title: const Text('Create Secure Session',
            style: TextStyle(color: Colors.white, fontSize: 17,
                fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: _loading
            ? _buildLoading()
            : _error != null
                ? _buildError()
                : _expired
                    ? _buildExpired()
                    : _buildContent(),
      ),
    );
  }

  // ── Loading state ────────────────────────────────────────────

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF00D4AA)),
          SizedBox(height: 20),
          Text('Generating key pair…',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      ),
    );
  }

  // ── Error state ──────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Expired state ─────────────────────────────────────────────

  Widget _buildExpired() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.redAccent.withOpacity(0.1),
                border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
              ),
              child: const Icon(Icons.timer_off_rounded,
                  color: Colors.redAccent, size: 36),
            ),
            const SizedBox(height: 20),
            const Text('Session Expired',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(
              'No one joined in time. The session key has been discarded.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Main content ─────────────────────────────────────────────

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: [
          // ── Status banner ─────────────────────────────────
          _buildStatusBanner(),
          const SizedBox(height: 24),

          // ── QR Code ───────────────────────────────────────
          _buildQrCard(),
          const SizedBox(height: 20),

          // ── Timer ─────────────────────────────────────────
          _buildTimer(),
          const SizedBox(height: 20),

          // ── Raw payload (dev helper) ───────────────────────
          _buildPayloadBox(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF00D4AA).withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00D4AA).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          // Pulsing dot
          _PulsingDot(color: const Color(0xFF00D4AA)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Waiting for participant to scan…',
              style: TextStyle(
                  color: Color(0xFF00D4AA),
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF141824),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        children: [
          const Text('Session QR Code',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Have the other device scan or paste this QR payload',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
          const SizedBox(height: 20),
          // QR Code
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: _qrPayload!,
              version: QrVersions.auto,
              size: 280,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.all(12), // Quiet zone
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Session ID: ${_session!.sessionId.substring(0, 8)}…',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildTimer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF141824),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _timerColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined, color: _timerColor, size: 18),
              const SizedBox(width: 8),
              Text('Session expires in',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
            ],
          ),
          Text(
            _timeLabel,
            style: TextStyle(
              color: _timerColor,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayloadBox() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF141824),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.code_rounded,
                        size: 15, color: Colors.grey.shade500),
                    const SizedBox(width: 8),
                    Text('QR Payload (dev)',
                        style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                TextButton.icon(
                  onPressed: _copyPayload,
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: const Text('Copy', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF00D4AA),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF252A3A), height: 16),
          // Selectable text payload
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SelectableText(
              _qrPayload!,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: Color(0xFF80FFD4),
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pulsing dot animation ────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
              shape: BoxShape.circle, color: widget.color),
        ),
      ),
    );
  }
}
