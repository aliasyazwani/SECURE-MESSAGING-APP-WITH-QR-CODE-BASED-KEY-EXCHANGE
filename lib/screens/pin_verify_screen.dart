// ============================================================
//  screens/pin_verify_screen.dart
//  DEPRECATED — Local PIN authentication has been removed.
//  PIN verification is no longer part of the auth flow.
//  This file is kept to avoid breaking any residual imports
//  but is NOT referenced by any active screen.
//  New flow: Firebase Auth → TOTP Verify → HomeScreen.
// ============================================================

import 'package:flutter/material.dart';
import 'totp_verify_screen.dart';

/// Deprecated. Redirects to TotpVerifyScreen if somehow reached.
class PinVerifyScreen extends StatelessWidget {
  const PinVerifyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Redirect immediately to TOTP verification
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const TotpVerifyScreen()),
      );
    });
    return const Scaffold(
      backgroundColor: Color(0xFF0A0E1A),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF00D4AA)),
      ),
    );
  }
}
