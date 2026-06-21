// ============================================================
//  models/message_model.dart
//  Represents an encrypted message stored in Firestore.
//
//  SECURITY NOTES:
//  - 'ciphertext' is AES-256-GCM encrypted — opaque bytes, no plaintext.
//  - 'nonce' is a random 12-byte IV unique per message.
//  - Decryption happens locally using the in-memory session key.
//  - Firestore never sees plaintext.
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  final String messageId;
  final String senderUid;
  final String senderEmail;

  /// Display name of the sender (if available).
  final String? senderDisplayName;

  /// AES-256-GCM ciphertext (Base64-encoded).
  final String ciphertext;

  /// Random 12-byte GCM nonce (Base64-encoded). Unique per message.
  final String nonce;

  /// GCM authentication tag/MAC (Base64-encoded).
  final String mac;

  /// Default: "text"
  final String messageType;

  final DateTime createdAt;

  // Transient field used by the UI to hold decrypted text after loading.
  // This is NEVER saved to Firestore.
  String? decryptedText;

  MessageModel({
    required this.messageId,
    required this.senderUid,
    required this.senderEmail,
    this.senderDisplayName,
    required this.ciphertext,
    required this.nonce,
    required this.mac,
    this.messageType = 'text',
    required this.createdAt,
    this.decryptedText,
  });

  factory MessageModel.fromMap(Map<String, dynamic> map, String id) {
    return MessageModel(
      messageId: id,
      senderUid: map['senderUid'] as String,
      senderEmail: map['senderEmail'] as String,
      senderDisplayName: map['senderDisplayName'] as String?,
      ciphertext: map['ciphertext'] as String,
      nonce: map['nonce'] as String,
      mac: (map['mac'] as String?) ?? '',
      messageType: map['messageType'] as String? ?? 'text',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderUid': senderUid,
      'senderEmail': senderEmail,
      if (senderDisplayName != null) 'senderDisplayName': senderDisplayName,
      'ciphertext': ciphertext,
      'nonce': nonce,
      'mac': mac,
      'messageType': messageType,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
