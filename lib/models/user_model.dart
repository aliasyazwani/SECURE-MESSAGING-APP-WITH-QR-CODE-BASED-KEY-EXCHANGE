// ============================================================
//  models/user_model.dart
//  Data model for a registered SecureLink user.
//  Only non-sensitive public info is stored in Firestore.
//  No keys, no secrets — those stay on-device only.
//
//  Firestore fields (users/{uid}):
//    uid          – Firebase Auth UID
//    email        – lowercase email
//    displayName  – chosen display name
//    totpEnabled  – true once TOTP enrolment is complete
//    createdAt    – account creation timestamp
//    updatedAt    – last profile-change timestamp
//
//  SECURITY: TOTP secret is NEVER included here.
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final bool totpEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    this.totpEnabled = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Build from a Firestore document snapshot.
  factory UserModel.fromMap(Map<String, dynamic> map) {
    DateTime _ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return DateTime.now();
    }

    return UserModel(
      uid: map['uid'] as String,
      email: map['email'] as String,
      displayName: map['displayName'] as String,
      totpEnabled: (map['totpEnabled'] as bool?) ?? false,
      createdAt: _ts(map['createdAt']),
      updatedAt: _ts(map['updatedAt']),
    );
  }

  /// Serialize to Firestore-compatible map.
  /// SECURITY: No keys or secrets ever included.
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'totpEnabled': totpEnabled,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  /// Return a copy with updated fields.
  UserModel copyWith({
    bool? totpEnabled,
    DateTime? updatedAt,
  }) {
    return UserModel(
      uid: uid,
      email: email,
      displayName: displayName,
      totpEnabled: totpEnabled ?? this.totpEnabled,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
