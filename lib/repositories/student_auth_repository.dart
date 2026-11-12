import 'package:cloud_firestore/cloud_firestore.dart';

abstract class IStudentAuthRepository {
  Future<Map<String, dynamic>> loginAndVerifyDevice(String studentId, String email, String currentDeviceId);
  Future<void> requestDeviceReset(String studentId, String reason);
}

class FirebaseStudentAuthRepository implements IStudentAuthRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Future<Map<String, dynamic>> loginAndVerifyDevice(String studentId, String email, String currentDeviceId) async {
    // 1. CLOUD DEVICE GATEKEEPER: Check if this phone is already owned by someone else
    final deviceCheck = await _firestore.collection('users')
        .where('registeredDeviceId', isEqualTo: currentDeviceId)
        .get(const GetOptions(source: Source.server));

    if (deviceCheck.docs.isNotEmpty) {
      final ownerId = deviceCheck.docs.first.id;
      if (ownerId != studentId) {
        throw Exception('SECURITY_VIOLATION: Proxy Detected. This physical phone belongs to a different student ID.');
      }
    }

    DocumentReference userRef = _firestore.collection('users').doc(studentId);
    DocumentSnapshot userSnap = await userRef.get(const GetOptions(source: Source.server));

    if (!userSnap.exists) {
      // First time registration: Bind this device to this new account
      await userRef.set({
        'studentId': studentId,
        'email': email,
        'name': 'Student $studentId',
        'registeredDeviceId': currentDeviceId,
        'hasConsented': false,
        'deviceResetStatus': 'none',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return {
        'studentName': 'Student $studentId',
        'hasConsented': false,
      };
    } else {
      // Returning user check
      Map<String, dynamic> userData = userSnap.data() as Map<String, dynamic>;
      String? fetchedToken = userData['registeredDeviceId'];
      final hasConsented = userData['hasConsented'] == true;
      final studentName = userData['name'] ?? 'Student';

      if (fetchedToken == null || fetchedToken.isEmpty) {
        // Automatically claim the device if the token is empty (Admin approved reset)
        await userRef.update({'registeredDeviceId': currentDeviceId});
        return {
          'studentName': studentName,
          'hasConsented': hasConsented,
        };
      } else if (fetchedToken != currentDeviceId) {
        throw Exception('SECURITY_VIOLATION: Account Proxy Detected.');
      } else {
        return {
          'studentName': studentName,
          'hasConsented': hasConsented,
        };
      }
    }
  }

  @override
  Future<void> requestDeviceReset(String studentId, String reason) async {
    await _firestore.collection('users').doc(studentId).set({
      'deviceResetStatus': 'pending',
      'deviceResetReason': reason,
    }, SetOptions(merge: true));
  }
}
