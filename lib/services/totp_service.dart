// ============================================================
//  services/totp_service.dart
//  TOTP (Time-based One-Time Password) utilities.
//
//  Implements RFC 6238 / RFC 4226 via the `otp` package.
//  Generates Google Authenticator / Microsoft Authenticator
//  compatible secrets and otpauth:// URIs.
//
//  SECURITY NOTES:
//  - Secret is generated using cryptographically random bytes.
//  - Verification checks window ±1 step (30s grace period).
//  - Secret is NEVER logged or sent to any server.
// ============================================================

import 'dart:math';
import 'dart:typed_data';
import 'package:otp/otp.dart';

class TotpService {
  // ── Base32 alphabet (RFC 4648) ─────────────────────────────
  static const _base32Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  // ── Secret Generation ──────────────────────────────────────

  /// Generate a cryptographically random 20-byte base32 secret.
  /// Compatible with Google Authenticator and Microsoft Authenticator.
  static String generateSecret() {
    final rng = Random.secure();
    final bytes = Uint8List(20);
    for (int i = 0; i < 20; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return _base32Encode(bytes);
  }

  /// Encode raw bytes to base32 (RFC 4648, no padding).
  static String _base32Encode(Uint8List data) {
    final output = StringBuffer();
    int buffer = 0;
    int bitsLeft = 0;

    for (final byte in data) {
      buffer = (buffer << 8) | (byte & 0xFF);
      bitsLeft += 8;
      while (bitsLeft >= 5) {
        bitsLeft -= 5;
        output.write(_base32Chars[(buffer >> bitsLeft) & 0x1F]);
      }
    }

    if (bitsLeft > 0) {
      output.write(_base32Chars[(buffer << (5 - bitsLeft)) & 0x1F]);
    }

    return output.toString();
  }

  // ── URI Generation ─────────────────────────────────────────

  /// Build an otpauth:// URI for QR code display.
  /// Format: otpauth://totp/{label}?secret={secret}&issuer={issuer}&algorithm=SHA1&digits=6&period=30
  ///
  /// This format is directly scannable by Google Authenticator,
  /// Microsoft Authenticator, and Aegis.
  static String buildOtpAuthUri({
    required String secret,
    required String email,
    String issuer = 'SecureLink',
  }) {
    final encodedEmail = Uri.encodeComponent(email);
    final encodedIssuer = Uri.encodeComponent(issuer);
    return 'otpauth://totp/$encodedIssuer:$encodedEmail'
        '?secret=$secret'
        '&issuer=$encodedIssuer'
        '&algorithm=SHA1'
        '&digits=6'
        '&period=30';
  }

  // ── Code Verification ──────────────────────────────────────

  /// Verify a 6-digit TOTP code against a base32 secret.
  ///
  /// Checks the current 30-second window plus one step before
  /// and after to account for clock drift.
  /// Returns true if the code is valid.
  static bool verifyCode(String secret, String code) {
    if (code.length != 6) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    const stepMs = 30 * 1000;

    // Check current window and ±1 step for clock drift tolerance
    for (final offset in [-1, 0, 1]) {
      final windowTime = now + (offset * stepMs);
      final expected = OTP.generateTOTPCodeString(
        secret,
        windowTime,
        algorithm: Algorithm.SHA1,
        isGoogle: true,
      );
      if (expected == code.trim()) return true;
    }
    return false;
  }

  /// Generate the current TOTP code (for testing/display only).
  /// Not used in production verification flow.
  static String generateCurrentCode(String secret) {
    return OTP.generateTOTPCodeString(
      secret,
      DateTime.now().millisecondsSinceEpoch,
      algorithm: Algorithm.SHA1,
      isGoogle: true,
    );
  }
}
