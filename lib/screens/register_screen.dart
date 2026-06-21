// ============================================================
//  screens/register_screen.dart
//  User registration: Firebase Auth + Firestore user doc.
//  After success → TotpSetupScreen (TOTP must be configured
//  before accessing the app).
// ============================================================

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/loading_button.dart';
import 'totp_setup_screen.dart';
import 'login_screen.dart';
import '../utils/password_validator.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  final _authService = AuthService();
  bool _isLoading = false;
  String? _errorMessage;

  bool isPasswordValid = false;
  String passwordStrength = "";

  @override
  void initState() {
    super.initState();

    _passwordController.addListener(() {
      final password = _passwordController.text;
      final error = PasswordValidator.validate(password);

      setState(() {
        isPasswordValid = error == null;

        if (password.isEmpty) {
          passwordStrength = "";
        } else if (error == null) {
          passwordStrength = "Strong";
        } else if (password.length >= 6) {
          passwordStrength = "Medium";
        } else {
          passwordStrength = "Weak";
        }
      });
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.register(
        email: _emailController.text,
        password: _passwordController.text,
        displayName: _nameController.text.trim(),
      );

      if (!mounted) return;

      // Registration complete. Go to TOTP setup — required before use.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const TotpSetupScreen()),
      );
    } on Exception catch (e) {
      setState(() => _errorMessage = _friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('email-already-in-use')) {
      return 'An account with this email already exists.';
    } else if (raw.contains('weak-password')) {
      return 'Password is too weak. Use at least 6 characters.';
    } else if (raw.contains('invalid-email')) {
      return 'Invalid email address.';
    }
    return 'Registration failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Brand header ──────────────────────────────
                const SizedBox(height: 16),
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
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 40),
                const Text(
                  'Create Account',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Set up your secure messaging account',
                  style:
                      TextStyle(color: Colors.grey.shade500, fontSize: 14),
                ),

                const SizedBox(height: 32),

                // ── Form fields ───────────────────────────────
                CustomTextField(
                  label: 'Display Name',
                  controller: _nameController,
                  prefixIcon: const Icon(Icons.person_outline),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Name is required'
                      : null,
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Email Address',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: const Icon(Icons.email_outlined),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Email is required';
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Password',
                  controller: _passwordController,
                  obscureText: true,
                  prefixIcon: const Icon(Icons.lock_outline),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Password is required';
                    }
                    final error = PasswordValidator.validate(v);
                    if (error != null) {
                      return error;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 6),

                Text(
                  "Password must contain:",
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 4),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text("• At least 8 characters", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Text("• 1 uppercase letter (A-Z)", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Text("• 1 lowercase letter (a-z)", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Text("• 1 number (0-9)", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Text("• 1 special character (!@#\$...)", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),

                if (passwordStrength.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      "Strength: $passwordStrength",
                      style: TextStyle(
                        color: passwordStrength == "Strong"
                            ? Colors.green
                            : passwordStrength == "Medium"
                            ? Colors.orange
                            : Colors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Confirm Password',
                  controller: _confirmController,
                  obscureText: true,
                  prefixIcon: const Icon(Icons.lock_outline),
                  validator: (v) {
                    if (v != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.redAccent.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.redAccent, size: 18),
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
                  label: 'Create Account',
                  isLoading: _isLoading,
                  onPressed: isPasswordValid ? _register : null,
                ),

                const SizedBox(height: 20),

                // ── Info box ──────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2130),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline,
                          color: Color(0xFF00D4AA), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'After registration you will link your authenticator app (Google Authenticator / Microsoft Authenticator) for 2-factor security.',
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 14),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                            builder: (_) => const LoginScreen()),
                      ),
                      child: const Text(
                        'Sign In',
                        style: TextStyle(
                          color: Color(0xFF00D4AA),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
