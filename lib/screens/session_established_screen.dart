// ============================================================
//  screens/session_established_screen.dart
//  Shown after a successful ECDH key exchange.
//
//  Receives:
//    • session      – SessionModel (public metadata only)
//    • sharedKeyBytes – the 32-byte derived AES key (in memory only)
//    • isHost       – true if this device created the session
//
//  SECURITY: sharedKeyBytes is held only in this widget's state.
//  It is NEVER written to disk, Firestore, or secure storage.
//  It will be passed forward to the encrypted chat screen in Phase 4.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/session_model.dart';
import '../services/session_service.dart';
import 'encrypted_chat_screen.dart';
import 'home_screen.dart';

class SessionEstablishedScreen extends StatefulWidget {
  final SessionModel session;

  /// The 32-byte derived shared key — kept only in memory.
  final List<int> sharedKeyBytes;

  /// True if this device is the session host.
  final bool isHost;

  const SessionEstablishedScreen({
    super.key,
    required this.session,
    required this.sharedKeyBytes,
    required this.isHost,
  });

  @override
  State<SessionEstablishedScreen> createState() =>
      _SessionEstablishedScreenState();
}

class _SessionEstablishedScreenState extends State<SessionEstablishedScreen>
    with SingleTickerProviderStateMixin {
  final _sessionService = SessionService();

  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  bool _keyVisible = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scaleAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _animController,
          curve: const Interval(0.3, 1.0, curve: Curves.easeOut)),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────

  /// Hex representation of the first 8 bytes of the shared key for display.
  String get _keyPreview {
    final hex = widget.sharedKeyBytes
        .take(8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    return '$hex …';
  }

  String get _fullKeyHex => widget.sharedKeyBytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join(' ');

  String get _shortSessionId =>
      '${widget.session.sessionId.substring(0, 8)}…'
      '${widget.session.sessionId.substring(widget.session.sessionId.length - 4)}';

  String get _myRole => widget.isHost ? 'Host' : 'Participant';
  String get _myEmail => widget.isHost
      ? widget.session.createdByEmail
      : (widget.session.joinedByEmail ?? '—');
  String get _theirEmail => widget.isHost
      ? (widget.session.joinedByEmail ?? '—')
      : widget.session.createdByEmail;

  Future<void> _endSession() async {
    await _sessionService.endSession(widget.session.sessionId);
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Secure session ended.'),
        backgroundColor: Color(0xFF00D4AA),
        duration: Duration(seconds: 3),
      ),
    );

    // Navigate to HomeScreen and remove everything else
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Column(
              children: [
                // ── Success icon ───────────────────────────────
                _buildSuccessIcon(),
                const SizedBox(height: 24),

                // ── Title ──────────────────────────────────────
                const Text(
                  'Secure Session Established',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'End-to-end encrypted channel ready.\n'
                  'Shared key derived via X25519 + HKDF-SHA256.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.grey.shade500, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 32),

                // ── Session info card ───────────────────────────
                _buildSessionInfoCard(),
                const SizedBox(height: 16),

                // ── Key preview card ────────────────────────────
                _buildKeyCard(),
                const SizedBox(height: 16),

                // ── Crypto summary ──────────────────────────────
                _buildCryptoSummary(),
                const SizedBox(height: 32),

                // ── Continue to chat ────────────────────────────
                _buildChatButton(),
                const SizedBox(height: 12),

                // ── End session ─────────────────────────────────
                _buildEndButton(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Sub-widgets ──────────────────────────────────────────────

  Widget _buildSuccessIcon() {
    return ScaleTransition(
      scale: _scaleAnim,
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF00D4AA).withOpacity(0.1),
          border: Border.all(
              color: const Color(0xFF00D4AA).withOpacity(0.4), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00D4AA).withOpacity(0.2),
              blurRadius: 32,
              spreadRadius: 4,
            ),
          ],
        ),
        child: const Icon(Icons.lock_rounded,
            size: 40, color: Color(0xFF00D4AA)),
      ),
    );
  }

  Widget _buildSessionInfoCard() {
    return _InfoCard(
      title: 'Session Details',
      icon: Icons.info_outline_rounded,
      accentColor: const Color(0xFF00D4AA),
      children: [
        _InfoRow(
          label: 'Session ID',
          value: _shortSessionId,
          onCopy: () => _copy(widget.session.sessionId, 'Session ID'),
        ),
        _InfoRow(label: 'Your Role', value: _myRole),
        _InfoRow(label: 'Your Email', value: _myEmail),
        _InfoRow(label: 'Other Party', value: _theirEmail),
        _InfoRow(
          label: 'Status',
          value: 'Connected',
          valueColor: const Color(0xFF00D4AA),
        ),
      ],
    );
  }

  Widget _buildKeyCard() {
    return _InfoCard(
      title: 'Shared Session Key',
      icon: Icons.key_rounded,
      accentColor: const Color(0xFF7B61FF),
      children: [
        // Key preview / full toggle
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('AES-256 key (32 bytes)',
                    style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 11)),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _keyVisible = !_keyVisible),
                      child: Text(
                        _keyVisible ? 'Hide' : 'Show',
                        style: const TextStyle(
                            color: Color(0xFF7B61FF),
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => _copy(_fullKeyHex, 'Shared key'),
                      child: const Icon(Icons.copy_rounded,
                          size: 14, color: Color(0xFF7B61FF)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF7B61FF).withOpacity(0.2)),
              ),
              child: SelectableText(
                _keyVisible ? _fullKeyHex : _keyPreview,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  color: Color(0xFFB8A0FF),
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 12, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  'This key exists only in memory — never stored anywhere.',
                  style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 10,
                      height: 1.3),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCryptoSummary() {
    final steps = [
      ('X25519 ECDH', 'Ephemeral key exchange', Icons.swap_horiz_rounded),
      ('HKDF-SHA256', 'Key derivation (salt=sessionId)', Icons.compress_rounded),
      ('AES-256-GCM', 'Ready for Phase 4 encryption', Icons.lock_outlined),
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
              Icon(Icons.security_rounded,
                  size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 8),
              Text('Cryptographic pipeline',
                  style: TextStyle(
                      color: Colors.grey.shade300,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 14),
          ...steps.map((s) {
            final (title, sub, icon) = s;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00D4AA).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon,
                        size: 17, color: const Color(0xFF00D4AA)),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      Text(sub,
                          style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 11)),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildChatButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00D4AA),
          foregroundColor: const Color(0xFF0A0E1A),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        onPressed: () {
          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => EncryptedChatScreen(
                session: widget.session,
                sharedKeyBytes: widget.sharedKeyBytes,
              ),
              transitionDuration: const Duration(milliseconds: 350),
              transitionsBuilder: (_, anim, __, child) =>
                  FadeTransition(opacity: anim, child: child),
            ),
          );
        },
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 18),
            SizedBox(width: 8),
            Text('Continue to Encrypted Chat',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _buildEndButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.redAccent,
          side: BorderSide(color: Colors.redAccent.withOpacity(0.4)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: _endSession,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.link_off_rounded, size: 17),
            SizedBox(width: 8),
            Text('End Session',
                style:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ── Utility ──────────────────────────────────────────────────

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// ── Reusable card ─────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final List<Widget> children;

  const _InfoCard({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141824),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: accentColor),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      color: accentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFF252A3A), height: 1),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

// ── Info row ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onCopy;

  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(
                    color: Colors.grey.shade500, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onCopy != null)
            GestureDetector(
              onTap: onCopy,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.copy_rounded,
                    size: 13, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }
}
