// ============================================================
//  screens/secure_session_menu_screen.dart
//  Entry screen for the Secure Session flow.
//  Presents two options: Create or Join a session.
// ============================================================

import 'package:flutter/material.dart';
import 'create_session_screen.dart';
import 'join_session_screen.dart';

class SecureSessionMenuScreen extends StatefulWidget {
  const SecureSessionMenuScreen({super.key});

  @override
  State<SecureSessionMenuScreen> createState() =>
      _SecureSessionMenuScreenState();
}

class _SecureSessionMenuScreenState extends State<SecureSessionMenuScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _slideAnim =
        Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _openCreate() {
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, __, ___) => const CreateSessionScreen(),
      transitionDuration: const Duration(milliseconds: 350),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  void _openJoin() {
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, __, ___) => const JoinSessionScreen(),
      transitionDuration: const Duration(milliseconds: 350),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

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
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Secure Session',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ─────────────────────────────────
                  _buildHeader(),
                  const SizedBox(height: 40),

                  // ── Options ────────────────────────────────
                  _SessionOptionCard(
                    icon: Icons.add_link_rounded,
                    title: 'Create New Secure Session',
                    description:
                        'Generate a one-time session key pair and share the QR code with another device.',
                    accentColor: const Color(0xFF00D4AA),
                    features: const [
                      'Generates ephemeral X25519 key pair',
                      'Shows QR code for the other party',
                      'Session expires in 10 minutes',
                    ],
                    onTap: _openCreate,
                  ),
                  const SizedBox(height: 16),
                  _SessionOptionCard(
                    icon: Icons.link_rounded,
                    title: 'Join Secure Session',
                    description:
                        'Paste a QR payload from the session host to join and establish shared encryption.',
                    accentColor: const Color(0xFF7B61FF),
                    features: const [
                      'Validates session before joining',
                      'Derives shared key via ECDH locally',
                      'No keys stored anywhere',
                    ],
                    onTap: _openJoin,
                  ),

                  const SizedBox(height: 40),

                  // ── Security note ──────────────────────────
                  _buildSecurityNote(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF00D4AA).withOpacity(0.1),
            border: Border.all(
                color: const Color(0xFF00D4AA).withOpacity(0.3), width: 1.5),
          ),
          child: const Icon(Icons.vpn_lock_rounded,
              size: 28, color: Color(0xFF00D4AA)),
        ),
        const SizedBox(height: 20),
        const Text(
          'End-to-End Encrypted\nSession',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Choose whether you want to host a new session or join one '
          'created by another device.',
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildSecurityNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141824),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined,
              size: 18, color: Colors.grey.shade500),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'All keys are generated on-device and kept in memory. '
              'Private keys are never stored or transmitted.',
              style: TextStyle(
                  color: Colors.grey.shade500, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Option Card ─────────────────────────────────────────────────────────────

class _SessionOptionCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color accentColor;
  final List<String> features;
  final VoidCallback onTap;

  const _SessionOptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.accentColor,
    required this.features,
    required this.onTap,
  });

  @override
  State<_SessionOptionCard> createState() => _SessionOptionCardState();
}

class _SessionOptionCardState extends State<_SessionOptionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: _hovered
              ? const Color(0xFF1A2030)
              : const Color(0xFF141824),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hovered
                ? widget.accentColor.withOpacity(0.4)
                : Colors.grey.shade800,
            width: 1.2,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                      color: widget.accentColor.withOpacity(0.08),
                      blurRadius: 20,
                      spreadRadius: 2)
                ]
              : [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: widget.accentColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(widget.icon,
                            color: widget.accentColor, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          color: widget.accentColor.withOpacity(0.7), size: 22),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.description,
                    style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                        height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  // Feature pills
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.features
                        .map((f) => _FeaturePill(
                            label: f, color: widget.accentColor))
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final String label;
  final Color color;
  const _FeaturePill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 11, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
