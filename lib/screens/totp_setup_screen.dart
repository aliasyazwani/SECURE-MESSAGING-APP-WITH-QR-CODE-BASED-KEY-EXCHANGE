// ============================================================
//  screens/totp_setup_screen.dart
//  TOTP Enrolment — Step 2 of 2 (new users / first-time setup).
//
//  Flow:
//  1. Generates a secure base32 TOTP secret on init.
//  2. Builds an otpauth:// URI and renders it as a QR code.
//  3. Shows the raw secret as selectable text.
//  4. User scans QR with Google/Microsoft Authenticator.
//  5. User enters the 6-digit code shown in their app.
//  6. On success → saves secret to flutter_secure_storage,
//     marks Firestore totpEnabled = true, routes to HomeScreen.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/secure_storage_service.dart';
import '../services/totp_service.dart';
import '../widgets/loading_button.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class TotpSetupScreen extends StatefulWidget {
  const TotpSetupScreen({super.key});

  @override
  State<TotpSetupScreen> createState() => _TotpSetupScreenState();
}

class _TotpSetupScreenState extends State<TotpSetupScreen> {
  final _codeController = TextEditingController();
  final _authService = AuthService();
  final _storage = SecureStorageService();

  String? _secret;
  String? _otpAuthUri;
  bool _isLoading = false;
  String? _errorMessage;
  bool _secretCopied = false;

  @override
  void initState() {
    super.initState();
    _generateSecret();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _generateSecret() {
    final user = FirebaseAuth.instance.currentUser;
    final secret = TotpService.generateSecret();
    final uri = TotpService.buildOtpAuthUri(
      secret: secret,
      email: user?.email ?? 'user@securelink',
      issuer: 'SecureLink',
    );
    setState(() {
      _secret = secret;
      _otpAuthUri = uri;
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
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Enter the 6-digit code from your authenticator app.');
      return;
    }
    if (_secret == null) return;

    // Check OTP lockout
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
        // Save secret locally — NEVER to Firestore
        await _storage.saveTotpSecret(_secret!);
        await _storage.resetOtpAttempts();

        // Mark totpEnabled = true in Firestore (safe metadata only)
        final uid = FirebaseAuth.instance.currentUser!.uid;
        await _authService.markTotpEnabled(uid);

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
        setState(() => _errorMessage = attempts >= 5
            ? 'Too many failed attempts. Locked for 5 minutes.'
            : 'Incorrect code. Check your authenticator app and try again. (${5 - attempts} attempts left)');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Verification failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _copySecret() async {
    if (_secret == null) return;
    await Clipboard.setData(ClipboardData(text: _secret!));
    setState(() => _secretCopied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _secretCopied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ───────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00D4AA).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.lock_outline_rounded,
                        color: Color(0xFF00D4AA), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'SecureLink',
                    style: TextStyle(
                      color: Color(0xFF00D4AA),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              const Text(
                'Set Up Authenticator',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Step 2 of 2 — Link your authenticator app',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),

              const SizedBox(height: 24),

              // ── Info banner ──────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF7B61FF).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF7B61FF).withOpacity(0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline,
                        color: Color(0xFF7B61FF), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Open Google Authenticator or Microsoft Authenticator on your phone and scan the QR code below.',
                        style: TextStyle(
                            color: Colors.grey.shade300, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── QR Code ──────────────────────────────────────
              if (_otpAuthUri != null)
                Center(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00D4AA).withOpacity(0.15),
                              blurRadius: 30,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: QrImageView(
                          data: _otpAuthUri!,
                          version: QrVersions.auto,
                          size: 200,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Color(0xFF0A0E1A),
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Color(0xFF0A0E1A),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Center(child: CircularProgressIndicator()),

              const SizedBox(height: 24),

              // ── Secret key text ──────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2130),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF00D4AA).withOpacity(0.15)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Secret Key (manual entry)',
                      style:
                          TextStyle(color: Colors.grey.shade500, fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            _secret ?? '—',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _copySecret,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: _secretCopied
                                ? const Icon(Icons.check_rounded,
                                    key: ValueKey('check'),
                                    color: Color(0xFF00D4AA),
                                    size: 20)
                                : Icon(Icons.copy_rounded,
                                    key: const ValueKey('copy'),
                                    color: Colors.grey.shade500,
                                    size: 20),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── OTP Input ────────────────────────────────────
              Text(
                'Enter 6-digit code from your app',
                style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 10,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '000000',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 28,
                    letterSpacing: 10,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1E2130),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: Color(0xFF00D4AA), width: 1.5),
                  ),
                ),
                onChanged: (_) {
                  if (_errorMessage != null) {
                    setState(() => _errorMessage = null);
                  }
                },
              ),

              // ── Error message ────────────────────────────────
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.09),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.redAccent.withOpacity(0.35)),
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
                label: 'Verify & Enable',
                isLoading: _isLoading,
                onPressed: _verify,
              ),

              const SizedBox(height: 16),

              Center(
                child: Text(
                  'The secret key is stored only on this device.',
                  style:
                      TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
              ),
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
}
