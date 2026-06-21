// ============================================================
//  screens/pin_setup_screen.dart
//  DEPRECATED — Local PIN authentication has been removed.
//  PIN setup is no longer part of the auth flow.
//  This file is kept to avoid breaking any residual imports
//  but is NOT referenced by any active screen.
//  New flow: Firebase Auth → TOTP Setup → HomeScreen.
// ============================================================

import 'package:flutter/material.dart';
import 'totp_setup_screen.dart';

/// Deprecated. Redirects to TotpSetupScreen if somehow reached.
class PinSetupScreen extends StatelessWidget {
  const PinSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Redirect immediately to TOTP setup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const TotpSetupScreen()),
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
