import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:safe_device/safe_device.dart';

class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);

  @override
  String toString() => message;
}

class SecurityService {
  static Future<void> verifyDeviceSecurity(Position position) async {
    if (position.isMocked) {
      throw SecurityException('OS-level GPS spoofing detected.');
    }

    if (kIsWeb) {
      return;
    }

    try {
      final isMockLocation = await SafeDevice.isMockLocation;
      if (isMockLocation == true) {
        throw SecurityException('Mock location app detected.');
      }

      final isJailBroken = await SafeDevice.isJailBroken;
      if (isJailBroken == true) {
        throw SecurityException('Rooted or Jailbroken device detected.');
      }

      final isRealDevice = await SafeDevice.isRealDevice;
      if (isRealDevice == false) {
        throw SecurityException('Emulator detected.');
      }
    } catch (e) {
      if (e is SecurityException) rethrow;
      
      debugPrint('SECURITY_VIOLATION: Exception during environment integrity check: $e');
      throw SecurityException('Failed to verify device integrity.');
    }
  }
}
