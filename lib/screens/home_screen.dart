// ============================================================
//  screens/home_screen.dart
//  Post-authentication home. Reached only after both
//  Step 1 (Firebase Auth) and Step 2 (TOTP) are verified.
//
//  LOGOUT: Only calls FirebaseAuth.signOut(). Does NOT clear
//  flutter_secure_storage so the TOTP secret persists for
//  the next login session.
// ============================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'secure_session_menu_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  final _authService = AuthService();

  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    // Sign out from Firebase only.
    // IMPORTANT: Do NOT clear SecureStorageService here —
    // the TOTP secret must survive logout so the user can
    // verify their OTP on the next login.
    await _authService.signOut();

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LoginScreen(),
        transitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = _user?.email ?? 'Unknown';
    final displayName =
        _user?.displayName ?? email.split('@').first;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Top bar ───────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF00D4AA).withOpacity(0.15),
                            border: Border.all(
                                color: const Color(0xFF00D4AA)
                                    .withOpacity(0.4)),
                          ),
                          child: const Icon(Icons.lock_outline_rounded,
                              size: 20, color: Color(0xFF00D4AA)),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'SecureLink',
                          style: TextStyle(
                            color: Color(0xFF00D4AA),
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                    _authBadge(),
                  ],
                ),

                const SizedBox(height: 56),

                // ── Welcome card ──────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF00D4AA).withOpacity(0.08),
                        const Color(0xFF7B61FF).withOpacity(0.06),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFF00D4AA).withOpacity(0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome back,',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.email_outlined,
                              size: 14, color: Color(0xFF00D4AA)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              email,
                              style: TextStyle(
                                  color: Colors.grey.shade400, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _statusPill(Icons.check_circle_outline,
                              'Email Auth', true),
                          const SizedBox(width: 8),
                          _statusPill(
                              Icons.security, 'TOTP Verified', true),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                const Text(
                  'Actions',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Start Secure Session ──────────────────────
                _ActionCard(
                  icon: Icons.vpn_lock_rounded,
                  title: 'Start Secure Session',
                  subtitle: 'Begin an end-to-end encrypted chat',
                  accentColor: const Color(0xFF00D4AA),
                  onTap: () {
                    Navigator.of(context).push(PageRouteBuilder(
                      pageBuilder: (_, __, ___) =>
                          const SecureSessionMenuScreen(),
                      transitionDuration:
                          const Duration(milliseconds: 350),
                      transitionsBuilder: (_, anim, __, child) =>
                          FadeTransition(opacity: anim, child: child),
                    ));
                  },
                ),

                const SizedBox(height: 12),

                // ── Logout ────────────────────────────────────
                _ActionCard(
                  icon: Icons.logout_rounded,
                  title: 'Logout',
                  subtitle: 'Sign out (authenticator stays linked)',
                  accentColor: Colors.redAccent,
                  onTap: _logout,
                ),

                const Spacer(),

                Center(
                  child: Text(
                    'SecureLink • End-to-End Encrypted',
                    style: TextStyle(
                        color: Colors.grey.shade700, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _authBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF00D4AA).withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00D4AA).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: Color(0xFF00D4AA)),
          ),
          const SizedBox(width: 5),
          const Text(
            'Authenticated',
            style: TextStyle(
                color: Color(0xFF00D4AA),
                fontSize: 11,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(IconData icon, String label, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFF00D4AA).withOpacity(0.1)
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 12,
              color: active ? const Color(0xFF00D4AA) : Colors.grey),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: active ? const Color(0xFF00D4AA) : Colors.grey,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF141824),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.grey.shade600, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
