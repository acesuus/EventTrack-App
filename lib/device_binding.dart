import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thrown when this phone or the student's account is registered elsewhere.
class DeviceBindingException implements Exception {
  DeviceBindingException(this.message, {this.canRequestReset = false});
  final String message;

  /// True when the student's own account is bound to another phone, so an
  /// admin can move it to this one.
  final bool canRequestReset;
  @override
  String toString() => message;
}

/// One student account per phone, one phone per student account.
///
/// Phones are identified by a random ID created on first install
/// (`androidInfo.id` is the Android build number, shared by every phone on the
/// same firmware). Reinstalling the app creates a new ID, so the student needs
/// an admin to reset their device (Admin > Settings > update student, or a
/// reset request under Admin > Pending Requests).
class DeviceBinding {
  static const _installIdKey = 'install_id';
  static const _boundStudentKey = 'bound_student_id';

  static Future<String> installId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_installIdKey);
    if (existing != null) return existing;
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await prefs.setString(_installIdKey, id);
    return id;
  }

  /// Claims this phone for [studentId], or throws [DeviceBindingException].
  /// Offline, a phone already bound to this student is accepted.
  static Future<void> bind(String studentId) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = await installId();
    final firestore = FirebaseFirestore.instance;
    final deviceRef = firestore.collection('devices').doc(deviceId);
    final userRef = firestore.collection('users').doc(studentId);

    final DocumentSnapshot<Map<String, dynamic>> device;
    final DocumentSnapshot<Map<String, dynamic>> user;
    try {
      device = await deviceRef.get(const GetOptions(source: Source.server));
      user = await userRef.get(const GetOptions(source: Source.server));
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable' &&
          prefs.getString(_boundStudentKey) == studentId) {
        return;
      }
      if (e.code == 'unavailable') {
        throw DeviceBindingException(
          'Connect to the internet to register this phone.',
        );
      }
      rethrow;
    }

    final owner = device.data()?['studentId']?.toString();
    if (owner != null && owner != studentId) {
      throw DeviceBindingException(
        'This phone is already registered to another student account.',
      );
    }

    final bound = (user.data()?['registeredDeviceId'] ?? '').toString();
    if (bound.isNotEmpty && bound != deviceId) {
      throw DeviceBindingException(
        'Your account is registered to a different phone. Ask your admin to reset your device.',
        canRequestReset: true,
      );
    }

    if (bound.isEmpty || !device.exists) {
      final batch = firestore.batch();
      if (bound.isEmpty) {
        batch.set(userRef, {
          'studentId': studentId,
          'registeredDeviceId': deviceId,
        }, SetOptions(merge: true));
      }
      if (!device.exists) {
        batch.set(deviceRef, {
          'studentId': studentId,
          'boundAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    await prefs.setString(_boundStudentKey, studentId);
  }

  /// Signing out keeps the install ID and binding so the phone stays registered.
  static const keysToKeepOnLogout = {_installIdKey, _boundStudentKey};
}
