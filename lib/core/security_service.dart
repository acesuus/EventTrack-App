import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:safe_device/safe_device.dart';
import 'package:safe_device/safe_device_config.dart';

class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);

  @override
  String toString() => message;
}

/// Blocks attendance from spoofed GPS, emulators and rooted/jailbroken phones.
class SecurityService {
  static String? _deviceProblem;
  static bool _deviceChecked = false;

  static Future<void> verifyDeviceSecurity(Position position) async {
    if (position.isMocked) {
      throw SecurityException('A mock location app or GPS spoofer is on.');
    }
    if (kIsWeb) return;
    // The device itself doesn't change while tracking, so check it once.
    if (!_deviceChecked) {
      _deviceProblem = await _checkDevice();
      _deviceChecked = true;
    }
    if (_deviceProblem != null) throw SecurityException(_deviceProblem!);
  }

  static Future<String?> _checkDevice() async {
    try {
      // position.isMocked already covers mock locations; SafeDevice's own
      // check would run a second GPS listener.
      SafeDevice.init(const SafeDeviceConfig(mockLocationCheckEnabled: false));
      if (!await SafeDevice.isRealDevice) {
        return 'This looks like an emulator.';
      }
      if (await SafeDevice.isJailBroken) {
        return 'This phone is rooted or jailbroken.';
      }
    } catch (e) {
      // Don't lock students out if the check itself fails; GPS checks still apply.
      debugPrint('Device integrity check failed: $e');
    }
    return null;
  }

  /// Best effort: tracking stays blocked even if this write fails.
  static void logViolation(String studentId, String eventId, String reason) {
    FirebaseFirestore.instance
        .collection('security_logs')
        .add({
          'studentId': studentId,
          'eventId': eventId,
          'violationReason': reason,
          'timestamp': FieldValue.serverTimestamp(),
        })
        .then<void>(
          (_) {},
          onError: (Object e) => debugPrint('Security log not saved: $e'),
        );
  }
}
