// ============================================================
//  models/session_model.dart
//  Data model for a one-time secure session.
//
//  SECURITY NOTES:
//  - createdByPublicKey / joinedByPublicKey are X25519 PUBLIC keys
//    (hex-encoded). Safe to store in Firestore.
//  - The derived shared AES session key is NEVER stored here or
//    anywhere persistent. It lives only as a List<int> in memory.
//  - Status machine: "pending" → "active" → "ended"
//  - Sessions expire 10 minutes after creation.
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';

class SessionModel {
  final String sessionId;

  // ── Host ────────────────────────────────────────────────────
  final String createdByUid;
  final String createdByEmail;

  /// X25519 public key of the host, hex-encoded.
  /// Safe to store — this is a *public* key, not a secret.
  final String createdByPublicKey;

  // ── Participant ─────────────────────────────────────────────
  final String? joinedByUid;
  final String? joinedByEmail;

  /// X25519 public key of the participant, hex-encoded.
  /// Written by the participant after they join.
  final String? joinedByPublicKey;

  // ── Session ─────────────────────────────────────────────────
  final List<String> participantUids;
  final int maxParticipants;

  // ── Lifecycle ───────────────────────────────────────────────
  /// "pending"   – host is waiting for a participant
  /// "active"    – both public keys present, ECDH completed locally
  /// "ended"     – session closed (one-time use, anti-replay)
  final String status;

  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? joinedAt;

  // ── End Session ─────────────────────────────────────────────
  final DateTime? endedAt;
  final String? endedByUid;
  final String? endedByEmail;

  const SessionModel({
    required this.sessionId,
    required this.createdByUid,
    required this.createdByEmail,
    required this.createdByPublicKey,
    this.joinedByUid,
    this.joinedByEmail,
    this.joinedByPublicKey,
    required this.participantUids,
    required this.maxParticipants,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.joinedAt,
    this.endedAt,
    this.endedByUid,
    this.endedByEmail,
  });

  // ── Convenience getters ─────────────────────────────────────
  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';
  bool get isEnded => status == 'ended';

  // ── Firestore serialisation ─────────────────────────────────
  factory SessionModel.fromMap(Map<String, dynamic> map) {
    DateTime _tsToDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return DateTime.now();
    }

    return SessionModel(
      sessionId: map['sessionId'] as String,
      createdByUid: map['createdByUid'] as String,
      createdByEmail: map['createdByEmail'] as String,
      createdByPublicKey: map['createdByPublicKey'] as String,
      joinedByUid: map['joinedByUid'] as String?,
      joinedByEmail: map['joinedByEmail'] as String?,
      joinedByPublicKey: map['joinedByPublicKey'] as String?,
      participantUids: List<String>.from(map['participantUids'] ?? []),
      maxParticipants: map['maxParticipants'] as int? ?? 2,
      status: map['status'] as String? ?? 'pending',
      createdAt: _tsToDate(map['createdAt']),
      expiresAt: _tsToDate(map['expiresAt']),
      joinedAt: map['joinedAt'] != null ? _tsToDate(map['joinedAt']) : null,
      endedAt: map['endedAt'] != null ? _tsToDate(map['endedAt']) : null,
      endedByUid: map['endedByUid'] as String?,
      endedByEmail: map['endedByEmail'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'sessionId': sessionId,
        'createdByUid': createdByUid,
        'createdByEmail': createdByEmail,
        'createdByPublicKey': createdByPublicKey,
        'joinedByUid': joinedByUid,
        'joinedByEmail': joinedByEmail,
        'joinedByPublicKey': joinedByPublicKey,
        'participantUids': participantUids,
        'maxParticipants': maxParticipants,
        'status': status,
        'createdAt': Timestamp.fromDate(createdAt),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'joinedAt': joinedAt != null ? Timestamp.fromDate(joinedAt!) : null,
        'endedAt': endedAt != null ? Timestamp.fromDate(endedAt!) : null,
        'endedByUid': endedByUid,
        'endedByEmail': endedByEmail,
      };
}
