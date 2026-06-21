// ============================================================
//  screens/join_session_screen.dart
//  Participant flow:
//    1. Paste QR payload JSON into the text field.
//    2. Validate payload (JSON + Firestore checks).
//    3. Generate participant ephemeral X25519 key pair.
//    4. Write participant's PUBLIC key to Firestore (update doc).
//    5. Derive shared session key locally via X25519 + HKDF.
//    6. Navigate to SessionEstablishedScreen.
//
//  SECURITY: participantKeyPair (SimpleKeyPair) never leaves this
//  widget's state. The derived sharedKey is passed to the next
//  screen as a List<int> in-memory and never serialised.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/session_service.dart';
import 'session_established_screen.dart';
import 'qr_scanner_screen.dart';

class JoinSessionScreen extends StatefulWidget {
  const JoinSessionScreen({super.key});

  @override
  State<JoinSessionScreen> createState() => _JoinSessionScreenState();
}

class _JoinSessionScreenState extends State<JoinSessionScreen> {
  final _sessionService = SessionService();
  final _payloadController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  bool _joining = false;
  String? _validationError;

  @override
  void dispose() {
    _payloadController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Join logic ───────────────────────────────────────────────

  Future<void> _join() async {
    setState(() {
      _validationError = null;
    });

    final raw = _payloadController.text.trim();
    if (raw.isEmpty) {
      setState(() => _validationError = 'Please paste the QR payload first.');
      return;
    }

    // 1. Parse payload
    Map<String, dynamic> payload;
    try {
      payload = _sessionService.parseQrPayload(raw);
    } catch (_) {
      setState(() => _validationError = 'Invalid SecureLink QR code');
      return;
    }

    // Fast-fail expiry check — UTC-safe to avoid timezone false positives
    try {
      final expiresAt = DateTime.parse(payload['expiresAt']).toUtc();
      if (DateTime.now().toUtc().isAfter(expiresAt)) {
        setState(() => _validationError = 'Secure session QR has expired');
        return;
      }
    } catch (_) {
      setState(() => _validationError = 'Invalid SecureLink QR code');
      return;
    }

    setState(() => _joining = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;

      // 2. Join session (validates Firestore, generates key pair,
      //    derives shared key — all locally).
      final (session, sharedKey) = await _sessionService.joinSession(
        qrPayload: payload,
        participantUid: user.uid,
        participantEmail: user.email ?? '',
      );

      if (!mounted) return;

      // 3. Navigate to established screen with in-memory shared key
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder: (_, __, ___) => SessionEstablishedScreen(
          session: session,
          sharedKeyBytes: sharedKey,
          isHost: false,
        ),
        transitionDuration: const Duration(milliseconds: 350),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        
        final errorStr = e.toString();
        if (errorStr.contains('has expired')) {
          _validationError = 'Secure session QR has expired';
        } else if (errorStr.contains('has already been used')) {
          _validationError = 'This QR session has already been used.';
        } else if (errorStr.contains('has ended')) {
          _validationError = 'This secure session has ended.';
        } else if (errorStr.contains('own session')) {
          _validationError = 'You cannot join your own session.';
        } else {
          _validationError = 'Invalid SecureLink QR code';
        }
      });
    }
  }

  Future<void> _scanQr() async {
    final scannedCode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );

    if (scannedCode != null && scannedCode.isNotEmpty) {
      // Populate field and auto-join — scanner already validated the payload
      _payloadController.text = scannedCode;
      if (!mounted) return;
      await _join();
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      _payloadController.text = data.text!;
      if (_validationError != null) {
        setState(() => _validationError = null);
      }
    }
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
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Colors.white70, size: 20),
          onPressed:
              _joining ? null : () => Navigator.of(context).pop(),
        ),
        title: const Text('Join Secure Session',
            style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ───────────────────────────────────
                _buildHeader(),
                const SizedBox(height: 32),

                // ── Scan Button ───────────────────────────────
                _buildScanButton(),
                const SizedBox(height: 24),
                
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade800)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('OR', style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    Expanded(child: Divider(color: Colors.grey.shade800)),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Paste input ───────────────────────────────
                _buildPasteSection(),
                const SizedBox(height: 12),

                // ── Error message ─────────────────────────────
                if (_validationError != null) _buildError(),
                const SizedBox(height: 24),

                // ── Join button ───────────────────────────────
                _buildJoinButton(),
                const SizedBox(height: 32),

                // ── What happens next ─────────────────────────
                _buildInfoBox(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Sub-widgets ──────────────────────────────────────────────

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF7B61FF).withValues(alpha: 0.1),
            border: Border.all(
                color: const Color(0xFF7B61FF).withValues(alpha: 0.3), width: 1.5),
          ),
          child: const Icon(Icons.link_rounded,
              size: 26, color: Color(0xFF7B61FF)),
        ),
        const SizedBox(height: 18),
        const Text(
          'Join a Session',
          style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Paste the QR payload shared by the session host. '
          'Your device will generate its own key pair and '
          'derive the shared key locally.',
          style: TextStyle(
              color: Colors.grey.shade500, fontSize: 13, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildScanButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: _joining ? null : _scanQr,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF00D4AA),
          side: const BorderSide(color: Color(0xFF00D4AA)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.qr_code_scanner_rounded, size: 18),
            SizedBox(width: 8),
            Text('Scan QR Code',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _buildPasteSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'Manual QR Payload',
                  style: TextStyle(
                      color: Colors.grey.shade300,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B61FF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('JSON',
                      style: TextStyle(
                          color: Color(0xFF7B61FF),
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: _joining ? null : _pasteFromClipboard,
              icon: const Icon(Icons.paste_rounded, size: 14),
              label: const Text('Paste', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF00D4AA),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'If scanner is unavailable on emulator, paste the QR payload manually.',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 11, height: 1.4),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF141824),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _validationError != null
                  ? Colors.redAccent.withValues(alpha: 0.5)
                  : const Color(0xFF7B61FF).withValues(alpha: 0.2),
            ),
          ),
          child: TextField(
            controller: _payloadController,
            enabled: !_joining,
            maxLines: 10,
            minLines: 6,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Color(0xFF80C8FF),
              height: 1.6,
            ),
            decoration: InputDecoration(
              hintText:
                  '{\n  "sessionId": "...",\n  "createdByUid": "...",\n  "createdByPublicKey": "...",\n  "expiresAt": "..."\n}',
              hintStyle: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.grey.shade700,
                height: 1.6,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
              suffixIcon: _payloadController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded,
                          size: 18, color: Colors.grey),
                      onPressed: () {
                        _payloadController.clear();
                        setState(() => _validationError = null);
                      },
                    )
                  : null,
            ),
            onChanged: (_) {
              if (_validationError != null) {
                setState(() => _validationError = null);
              }
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tip: On the host device, tap "Copy" under the QR code, '
          'then paste here.',
          style: TextStyle(
              color: Colors.grey.shade600, fontSize: 11, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Colors.redAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _validationError!,
              style: const TextStyle(
                  color: Colors.redAccent, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJoinButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _joining ? null : _join,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7B61FF),
          disabledBackgroundColor: const Color(0xFF7B61FF).withValues(alpha: 0.4),
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: _joining
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Joining…',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ],
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.link_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('Join Secure Session',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ],
              ),
      ),
    );
  }

  Widget _buildInfoBox() {
    final steps = [
      (Icons.verified_outlined, 'Validate session payload'),
      (Icons.key_rounded, 'Generate your ephemeral X25519 key pair'),
      (Icons.cloud_upload_outlined, 'Upload your public key to Firestore'),
      (Icons.lock_rounded, 'Derive shared key locally via ECDH + HKDF'),
      (Icons.shield_outlined, 'Private key and shared key stay on device'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141824),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 15, color: Colors.grey.shade400),
              const SizedBox(width: 8),
              Text('What happens when you join',
                  style: TextStyle(
                      color: Colors.grey.shade300,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 14),
          ...steps.asMap().entries.map((e) {
            final i = e.key;
            final (icon, label) = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color:
                          const Color(0xFF7B61FF).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text('${i + 1}',
                          style: const TextStyle(
                              color: Color(0xFF7B61FF),
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label,
                        style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 12,
                            height: 1.3)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
