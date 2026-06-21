// ============================================================
//  services/session_service.dart
//  All session business logic: key generation, Firestore CRUD,
//  ECDH key exchange, HKDF derivation.
//
//  SECURITY ARCHITECTURE:
//  ┌─────────────────────────────────────────────────────────┐
//  │  What stays in Firestore (sessions/{sessionId}):        │
//  │  • sessionId, hostUid, hostEmail, hostPublicKey         │
//  │  • participantUid, participantEmail, participantPublicKey│
//  │  • status, createdAt, expiresAt, joinedAt               │
//  │                                                         │
//  │  What NEVER leaves the device:                          │
//  │  • Host ephemeral private key   (SimpleKeyPair)         │
//  │  • Participant ephemeral private key (SimpleKeyPair)    │
//  │  • Derived shared session key   (List<int> 32 bytes)    │
//  └─────────────────────────────────────────────────────────┘
//
//  Key derivation pipeline:
//    X25519 ECDH → raw shared secret (32 bytes)
//    → HKDF-SHA256 (salt=sessionId, info='SecureLink-v1')
//    → 32-byte AES-256-GCM ready key (kept in memory only)
// ============================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import '../models/session_model.dart';
import '../models/message_model.dart';

class SessionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _x25519 = X25519();
  static const _uuid = Uuid();

  // ── Hex helpers ─────────────────────────────────────────────

  /// Encode raw bytes to lowercase hex string.
  String bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Decode a lowercase hex string to bytes.
  List<int> hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  // ── Session Creation (Host) ──────────────────────────────────

  /// Generate a new session as the host.
  ///
  /// Returns a tuple of:
  ///   1. [SessionModel] – safe Firestore data (no private key).
  ///   2. [SimpleKeyPair] – host's ephemeral key pair.
  ///      MUST be kept in memory only. Never serialised or stored.
  ///
  /// Firestore document: sessions/{sessionId}
  Future<(SessionModel, SimpleKeyPair)> createSession({
    required String createdByUid,
    required String createdByEmail,
  }) async {
    final sessionId = _uuid.v4();

    // Generate ephemeral X25519 key pair — private key stays local
    final keyPair = await _x25519.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final createdByPublicKeyHex = bytesToHex(publicKey.bytes);

    final now = DateTime.now().toUtc();
    final expiresAt = now.add(const Duration(minutes: 10));

    final session = SessionModel(
      sessionId: sessionId,
      createdByUid: createdByUid,
      createdByEmail: createdByEmail,
      createdByPublicKey: createdByPublicKeyHex,
      // participant fields are null until someone joins
      joinedByUid: null,
      joinedByEmail: null,
      joinedByPublicKey: null,
      participantUids: [createdByUid],
      maxParticipants: 2,
      status: 'pending',
      createdAt: now,
      expiresAt: expiresAt,
    );

    // Write only public metadata — private key never touches Firestore
    await _firestore
        .collection('sessions')
        .doc(sessionId)
        .set(session.toMap());

    return (session, keyPair);
  }

  // ── Session Join (Participant) ───────────────────────────────

  /// Join an existing session using the parsed QR payload.
  ///
  /// Validates the payload, generates the participant key pair,
  /// updates Firestore (public key only), then derives the shared
  /// session key locally via X25519 + HKDF.
  ///
  /// Returns a tuple of:
  ///   1. [SessionModel] – updated session (connected state).
  ///   2. [List<int>] – 32-byte derived shared key (AES-256 ready).
  ///      MUST be kept in memory only. Never serialised or stored.
  Future<(SessionModel, List<int>)> joinSession({
    required Map<String, dynamic> qrPayload,
    required String participantUid,
    required String participantEmail,
  }) async {
    final sessionId = qrPayload['sessionId'] as String;
    final createdByPublicKeyHex = qrPayload['createdByPublicKey'] as String;
    final expiresAtStr = qrPayload['expiresAt'] as String;

    // --- Client-side expiry check (fast-fail before Firestore read) ---
    final expiresAt = DateTime.parse(expiresAtStr).toUtc();
    if (DateTime.now().toUtc().isAfter(expiresAt)) {
      throw Exception('Session has expired. Ask the host to create a new one.');
    }

    final docRef = _firestore.collection('sessions').doc(sessionId);

    // --- Generate participant ephemeral key pair ---
    final participantKeyPair = await _x25519.newKeyPair();
    final participantPublicKey = await participantKeyPair.extractPublicKey();
    final participantPublicKeyHex = bytesToHex(participantPublicKey.bytes);

    final now = DateTime.now();
    late SessionModel updatedSession;

    // --- Firestore Transaction ---
    await _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(docRef);
      if (!doc.exists) {
        throw Exception('Invalid SecureLink QR code');
      }

      final session = SessionModel.fromMap(doc.data()!);

      if (session.isEnded) {
        throw Exception('This secure session has ended.');
      }
      if (session.joinedByUid != null) {
        throw Exception('This QR session has already been used.');
      }
      if (!session.isPending) {
        throw Exception('Session is no longer available (status: ${session.status}).');
      }
      if (session.createdByUid == participantUid) {
        throw Exception('You cannot join your own session.');
      }

      // Update data
      transaction.update(docRef, {
        'joinedByUid': participantUid,
        'joinedByEmail': participantEmail,
        'participantUids': FieldValue.arrayUnion([participantUid]),
        'joinedByPublicKey': participantPublicKeyHex,
        'joinedAt': Timestamp.fromDate(now),
        'status': 'active',
      });

      updatedSession = SessionModel(
        sessionId: session.sessionId,
        createdByUid: session.createdByUid,
        createdByEmail: session.createdByEmail,
        createdByPublicKey: session.createdByPublicKey,
        joinedByUid: participantUid,
        joinedByEmail: participantEmail,
        joinedByPublicKey: participantPublicKeyHex,
        participantUids: [...session.participantUids, participantUid],
        maxParticipants: session.maxParticipants,
        status: 'active',
        createdAt: session.createdAt,
        expiresAt: session.expiresAt,
        joinedAt: now,
      );
    });

    // --- Derive shared session key locally (ECDH + HKDF) ---
    // This never leaves the device.
    final sharedKey = await deriveSharedKey(
      myKeyPair: participantKeyPair,
      theirPublicKeyHex: createdByPublicKeyHex,
      sessionId: sessionId,
    );

    return (updatedSession, sharedKey);
  }

  // ── Shared Key Derivation ────────────────────────────────────

  /// Derive a 32-byte shared session key via X25519 ECDH + HKDF-SHA256.
  ///
  /// Pipeline:
  ///   X25519(myPrivateKey, theirPublicKey) → ecdhSecret (raw 32 bytes)
  ///   HKDF-SHA256(salt=sessionId, info='SecureLink-v1') → 32-byte key
  ///
  /// The result is suitable for AES-256-GCM encryption.
  /// It MUST be stored only in memory (a Dart variable) — never serialised.
  Future<List<int>> deriveSharedKey({
    required SimpleKeyPair myKeyPair,
    required String theirPublicKeyHex,
    required String sessionId,
  }) async {
    final theirPublicKey = SimplePublicKey(
      hexToBytes(theirPublicKeyHex),
      type: KeyPairType.x25519,
    );

    // Step 1: X25519 ECDH → raw shared secret
    final ecdhSecret = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: theirPublicKey,
    );

    // Step 2: HKDF-SHA256 → deterministic 32-byte session key
    //   salt  = sessionId bytes  (binds key to this session)
    //   info  = 'SecureLink-v1' (domain separation)
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derivedKey = await hkdf.deriveKey(
      secretKey: ecdhSecret,
      nonce: utf8.encode(sessionId), // "nonce" == salt in this package
      info: utf8.encode('SecureLink-v1'),
    );

    return await derivedKey.extractBytes();
  }

  // ── Real-time Listener ───────────────────────────────────────

  /// Stream of live Firestore updates for a given session.
  /// Host uses this to detect when a participant joins.
  Stream<SessionModel?> watchSession(String sessionId) {
    return _firestore
        .collection('sessions')
        .doc(sessionId)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      return SessionModel.fromMap(snap.data()!);
    });
  }

  // ── Session Termination ──────────────────────────────────────

  /// Mark session as ended. Should be called when either party leaves.
  Future<void> endSession(String sessionId) async {
    try {
      await _firestore
          .collection('sessions')
          .doc(sessionId)
          .update({'status': 'ended'});
    } catch (_) {
      // Ignore if doc already removed / offline
    }
  }

  // ── QR Payload Helpers ───────────────────────────────────────

  /// Build the JSON string encoded in the QR code.
  /// Contains only public data — safe to transmit.
  String buildQrPayload(SessionModel session) {
    return const JsonEncoder.withIndent('  ').convert({
      'sessionId': session.sessionId,
      'createdByUid': session.createdByUid,
      'createdByPublicKey': session.createdByPublicKey,
      'expiresAt': session.expiresAt.toUtc().toIso8601String(),
    });
  }

  /// Parse and validate the structure of a raw QR payload string.
  /// Throws [FormatException] if any required field is missing.
  Map<String, dynamic> parseQrPayload(String raw) {
    late final Map<String, dynamic> map;
    try {
      map = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException(
          'Invalid JSON. Make sure you pasted the full payload.');
    }

    const required = ['sessionId', 'createdByUid', 'createdByPublicKey', 'expiresAt'];
    for (final key in required) {
      if (!map.containsKey(key) || map[key] == null) {
        throw FormatException('Payload is missing required field: "$key"');
      }
    }
    return map;
  }

  // ── Phase 4: Encrypted Chat ──────────────────────────────────

  /// Encrypts plaintext message locally using AES-256-GCM and stores
  /// only ciphertext in Firestore.
  Future<void> sendMessage({
    required String sessionId,
    required List<int> sharedKeyBytes,
    required String text,
    required String senderUid,
    required String senderEmail,
    String? senderDisplayName,
  }) async {
    final messageId = _uuid.v4();
    final aesGcm = AesGcm.with256bits();
    
    // Generate a fresh 12-byte random nonce
    final secretKey = SecretKey(sharedKeyBytes);
    final nonce = aesGcm.newNonce();
    
    // Encrypt
    final secretBox = await aesGcm.encrypt(
      utf8.encode(text),
      secretKey: secretKey,
      nonce: nonce,
    );
    
    final cipherTextB64 = base64Encode(secretBox.cipherText);
    final nonceB64 = base64Encode(secretBox.nonce);
    final macB64 = base64Encode(secretBox.mac.bytes);
    
    final message = MessageModel(
      messageId: messageId,
      senderUid: senderUid,
      senderEmail: senderEmail,
      senderDisplayName: senderDisplayName,
      ciphertext: cipherTextB64,
      nonce: nonceB64,
      mac: macB64,
      messageType: 'text',
      createdAt: DateTime.now(),
    );

    await _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('messages')
        .doc(messageId)
        .set(message.toMap());
  }

  /// Watch and locally decrypt messages for a session.
  Stream<List<MessageModel>> watchMessages(String sessionId, List<int> sharedKeyBytes) {
    return _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
      
      final aesGcm = AesGcm.with256bits();
      final secretKey = SecretKey(sharedKeyBytes);
      final messages = <MessageModel>[];

      for (var doc in snapshot.docs) {
        final msg = MessageModel.fromMap(doc.data(), doc.id);
        
        try {
          final nonceBytes = base64Decode(msg.nonce);
          final cipherTextBytes = base64Decode(msg.ciphertext);
          final macBytes = base64Decode(msg.mac);
          
          final secretBox = SecretBox(
            cipherTextBytes,
            nonce: nonceBytes,
            mac: Mac(macBytes),
          );
          
          final cleartextBytes = await aesGcm.decrypt(
            secretBox,
            secretKey: secretKey,
          );
          
          msg.decryptedText = utf8.decode(cleartextBytes);
        } catch (e) {
          debugPrint('Safe Debug: Decryption error for message ${msg.messageId}: $e');
          msg.decryptedText = '[Unable to decrypt message]';
        }
        
        messages.add(msg);
      }
      return messages;
    });
  }

  /// End session, delete all messages, and mark session as ended.
  /// Keeps the session document (for Firebase evidence) but wipes messages.
  Future<void> endChatSession(
    String sessionId, {
    String? endedByUid,
    String? endedByEmail,
  }) async {
    try {
      // 1. Update session status FIRST
      final sessionRef = _firestore.collection('sessions').doc(sessionId);
      await sessionRef.update({
        'status': 'ended',
        'endedAt': FieldValue.serverTimestamp(),
        if (endedByUid != null) 'endedByUid': endedByUid,
        if (endedByEmail != null) 'endedByEmail': endedByEmail,
      });

      // 2. Delete all messages in the subcollection AFTER status update
      // Do not await this, let it happen in background so it doesn't block navigation
      final messagesRef = sessionRef.collection('messages');
      messagesRef.get().then((snapshots) {
        if (snapshots.docs.isNotEmpty) {
          final batch = _firestore.batch();
          for (var doc in snapshots.docs) {
            batch.delete(doc.reference);
          }
          batch.commit();
        }
      }).catchError((_) {
        // Ignore deletion errors
      });
    } catch (_) {
      // Handle errors gracefully — offline or already ended
    }
  }
}
