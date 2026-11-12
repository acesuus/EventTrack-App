import 'dart:convert';
import 'package:crypto/crypto.dart';

class SecurityUtils {
  static const String _salt = "EventTrack_PSU_Secure_2026";

  static String generateAttendanceSignature(
    String studentId, 
    String eventId, 
    int timeInSeconds, 
    int timeInNanoseconds, 
    int totalOutsideSeconds
  ) {
    final String data = "$studentId$eventId$timeInSeconds$timeInNanoseconds$totalOutsideSeconds$_salt";
    return sha256.convert(utf8.encode(data)).toString();
  }
}
