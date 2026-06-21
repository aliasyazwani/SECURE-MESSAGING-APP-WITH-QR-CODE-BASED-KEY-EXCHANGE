// ============================================================
//  screens/totp_verify_screen.dart
//  TOTP Verification — Step 2 of 2 (returning users).
//
//  Flow:
//  1. Reads TOTP secret from flutter_secure_storage.
//  2. If secret missing → shows error (user must re-setup).
//  3. User enters 6-digit OTP from their authenticator app.
//  4. Verifies with ±1 time-step tolerance (RFC 6238).
//  5. On success → routes to HomeScreen.
//  6. Tracks failed attempts; locks for 5 min after 5 failures.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/secure_storage_service.dart';
import '../services/totp_service.dart';
import '../widgets/loading_button.dart';
import 'home_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';

class TotpVerifyScreen extends StatefulWidget {
  const TotpVerifyScreen({super.key});

  @override
  State<TotpVerifyScreen> createState() => _TotpVerifyScreenState();
}

class _TotpVerifyScreenState extends State<TotpVerifyScreen>
    with SingleTickerProviderStateMixin {
  final _codeController = TextEditingController();
  final _storage = SecureStorageService();

  String? _secret;
  bool _secretMissing = false;
  bool _isLoading = false;
  bool _isInitialising = true;
  String? _errorMessage;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticOut),
    );
    _loadSecret();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _loadSecret() async {
    final secret = await _storage.getTotpSecret();
    if (!mounted) return;
    setState(() {
      _secret = secret;
      _secretMissing = (secret == null || secret.isEmpty);
      _isInitialising = false;
    });
  }

  Future<void> _logoutAndGoBack() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _verify() async {
    if (_secret == null) return;

    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Enter the 6-digit code from your authenticator app.');
      return;
    }

    // Check lockout
    final lockout = await _storage.getOtpLockoutExpiry();
    if (lockout != null) {
      final remaining = lockout.difference(DateTime.now());
      setState(() => _errorMessage =
          'Too many attempts. Try again in ${remaining.inMinutes + 1} min.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final valid = TotpService.verifyCode(_secret!, code);

      if (valid) {
        await _storage.resetOtpAttempts();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionDuration: const Duration(milliseconds: 400),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
          (route) => false,
        );
      } else {
        await _storage.incrementOtpAttempts();
        final attempts = await _storage.getOtpAttempts();
        final msg = attempts >= 5
            ? 'Too many failed attempts. Locked for 5 minutes.'
            : 'Incorrect code. Try again. (${5 - attempts} attempts left)';
        setState(() => _errorMessage = msg);
        _codeController.clear();
        _shakeController.forward(from: 0);
      }
    } catch (e) {
      setState(() => _errorMessage = 'Verification failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: _isInitialising
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF00D4AA)))
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Brand ─────────────────────────────────
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF00D4AA).withOpacity(0.1),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      const Color(0xFF00D4AA).withOpacity(0.2),
                                  blurRadius: 30,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.security_rounded,
                              size: 40,
                              color: Color(0xFF00D4AA),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Verify Identity',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Step 2 of 2 — Authenticator OTP',
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 13),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),

                    // ── Secret missing error ──────────────────
                    if (_secretMissing) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.orange.withOpacity(0.35)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Colors.orange, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Authenticator Not Found',
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'TOTP secret not found on this device. This can happen if you reinstalled the app or changed devices.\n\nPlease contact support or reset your authenticator setup.',
                                    style: TextStyle(
                                        color: Colors.grey.shade300,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // ── Instructions ──────────────────────
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2130),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.smartphone_rounded,
                                color: Color(0xFF00D4AA), size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Open your authenticator app and enter the 6-digit code for SecureLink.',
                                style: TextStyle(
                                    color: Colors.grey.shade300,
                                    fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // ── OTP Input ─────────────────────────
                      AnimatedBuilder(
                        animation: _shakeAnim,
                        builder: (context, child) {
                          final offset = (_shakeAnim.value * 10) *
                              ((_shakeAnim.value * 4).round().isEven ? 1 : -1);
                          return Transform.translate(
                            offset: Offset(offset, 0),
                            child: child,
                          );
                        },
                        child: TextField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          autofocus: true,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 12,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: '000000',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 32,
                              letterSpacing: 12,
                            ),
                            filled: true,
                            fillColor: const Color(0xFF1E2130),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: Color(0xFF00D4AA), width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 20, horizontal: 16),
                          ),
                          onChanged: (_) {
                            if (_errorMessage != null) {
                              setState(() => _errorMessage = null);
                            }
                          },
                          onSubmitted: (_) => _verify(),
                        ),
                      ),

                      // ── Error ─────────────────────────────
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.09),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: Colors.redAccent.withOpacity(0.35)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Colors.redAccent, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                      color: Colors.redAccent, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 28),

                      LoadingButton(
                        label: 'Verify',
                        isLoading: _isLoading,
                        onPressed: _verify,
                      ),
                    ],

                    const SizedBox(height: 24),

                    // ── MFA step indicator ────────────────────
                    _buildStepIndicator(),

                    const SizedBox(height: 24),
                    Center(
                      child: TextButton.icon(
                        onPressed: _logoutAndGoBack,
                        icon: const Icon(Icons.logout_rounded, size: 16),
                        label: const Text('Back to Login'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2130),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '2-Factor Authentication',
            style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          _stepRow(1, 'Email & Password', done: true, active: false),
          _stepRow(2, 'Authenticator OTP', done: false, active: true),
        ],
      ),
    );
  }

  Widget _stepRow(int step, String label,
      {required bool done, required bool active}) {
    final color = done
        ? const Color(0xFF00D4AA)
        : active
            ? const Color(0xFF00D4AA)
            : const Color(0xFF2A2F45);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: Center(
              child: done
                  ? const Icon(Icons.check, size: 13, color: Color(0xFF0A0E1A))
                  : Text(
                      '$step',
                      style: TextStyle(
                        color: active
                            ? const Color(0xFF0A0E1A)
                            : Colors.grey.shade600,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: (done || active) ? Colors.white : Colors.grey.shade600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
