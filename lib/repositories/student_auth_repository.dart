import 'package:cloud_firestore/cloud_firestore.dart';

abstract class IStudentAuthRepository {
  Future<String> deviceResetStatus(String studentId);
  Future<void> requestDeviceReset(String studentId, String reason);
}

/// Device binding itself lives in DeviceBinding; this only handles reset requests.
class FirebaseStudentAuthRepository implements IStudentAuthRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Future<String> deviceResetStatus(String studentId) async =>
      (await _firestore.collection('users').doc(studentId).get())
          .data()?['deviceResetStatus']
          ?.toString() ??
      'none';

  @override
  Future<void> requestDeviceReset(String studentId, String reason) =>
      _firestore.collection('users').doc(studentId).set({
        'deviceResetStatus': 'pending',
        'deviceResetReason': reason,
        'deviceResetRequestedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
}
