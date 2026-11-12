import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

/// Tamper check for attendance records written by the student app.
///
/// shortcut: the salt ships inside the app, so this catches casual edits in the
/// Firebase console, not a determined attacker; move signing to a Cloud
/// Function with a secret key if that matters.
class SecurityUtils {
  static const String _salt = 'EventTrack_PSU_Secure_2026';

  static String attendanceSignature(Map<String, dynamic> record) {
    int ms(Object? t) => t is Timestamp ? t.millisecondsSinceEpoch : 0;
    final data = [
      record['studentId'],
      record['eventId'],
      record['status'],
      ms(record['timeIn']),
      ms(record['timeOut']),
      record['totalOutsideSeconds'] ?? 0,
      record['pointsAwarded'] ?? 0,
      _salt,
    ].join('|');
    return sha256.convert(utf8.encode(data)).toString();
  }

  /// [record] plus its signature.
  static Map<String, dynamic> signed(Map<String, dynamic> record) => {
    ...record,
    'signature': attendanceSignature(record),
  };

  /// True when a signed record was changed outside the app. Admin overrides
  /// and approved appeals are recorded separately, so they don't count.
  static bool looksTampered(Map<String, dynamic> record) {
    final signature = record['signature'];
    if (signature == null ||
        record['manualOverride'] == true ||
        record['appealStatus'] == 'approved') {
      return false;
    }
    return signature != attendanceSignature(record);
  }
}
