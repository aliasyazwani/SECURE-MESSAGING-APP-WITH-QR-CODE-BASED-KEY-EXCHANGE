// ============================================================
//  services/secure_storage_service.dart
//  Wraps flutter_secure_storage for all sensitive local data.
//
//  WHAT IS STORED HERE (and why):
//  - TOTP secret (base32)        — device-bound, RFC 6238 compliant
//  - OTP attempt counters        — for lockout logic (≥5 wrong codes)
//
//  WHAT IS NOT STORED HERE:
//  - Session AES keys            — kept in memory only, destroyed on exit
//  - Firebase credentials        — handled by Firebase SDK
//  - Private ephemeral keys      — generated per-session, never persisted
//  - TOTP secret in Firestore    — NEVER; device-bound only
//
//  flutter_secure_storage uses Android Keystore on Android,
//  which hardware-backs encryption where available.
// ============================================================

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  // ── Key constants ──────────────────────────────────────────
  static const _kTotpSecret = 'totp_secret';
  static const _kOtpAttempts = 'otp_attempts';
  static const _kOtpLockedUntil = 'otp_locked_until';

  // ── TOTP Storage ───────────────────────────────────────────

  /// Store TOTP secret locally (base32 encoded). Never sent to Firebase.
  /// PROTOTYPE NOTE: Device-bound. Reinstalling the app loses the secret.
  Future<void> saveTotpSecret(String secret) async {
    await _storage.write(key: _kTotpSecret, value: secret);
  }

  Future<String?> getTotpSecret() async {
    return await _storage.read(key: _kTotpSecret);
  }

  Future<bool> hasTotpSetup() async {
    final secret = await getTotpSecret();
    return secret != null && secret.isNotEmpty;
  }

  // ── OTP Lockout ────────────────────────────────────────────

  Future<int> getOtpAttempts() async {
    final val = await _storage.read(key: _kOtpAttempts);
    return int.tryParse(val ?? '0') ?? 0;
  }

  /// Increment failed OTP attempts. Locks for 5 min after 5 failures.
  Future<void> incrementOtpAttempts() async {
    final attempts = await getOtpAttempts() + 1;
    await _storage.write(key: _kOtpAttempts, value: attempts.toString());
    if (attempts >= 5) {
      final lockedUntil = DateTime.now().add(const Duration(minutes: 5));
      await _storage.write(
        key: _kOtpLockedUntil,
        value: lockedUntil.millisecondsSinceEpoch.toString(),
      );
    }
  }

  Future<void> resetOtpAttempts() async {
    await _storage.write(key: _kOtpAttempts, value: '0');
    await _storage.delete(key: _kOtpLockedUntil);
  }

  /// Returns null if not locked, or the DateTime when the lock expires.
  Future<DateTime?> getOtpLockoutExpiry() async {
    final val = await _storage.read(key: _kOtpLockedUntil);
    if (val == null) return null;
    final ms = int.tryParse(val);
    if (ms == null) return null;
    final expiry = DateTime.fromMillisecondsSinceEpoch(ms);
    if (DateTime.now().isAfter(expiry)) {
      await resetOtpAttempts();
      return null;
    }
    return expiry;
  }

  // ── Cleanup ────────────────────────────────────────────────

  /// Clear all stored data. Call on logout.
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
