import 'package:cloud_firestore/cloud_firestore.dart';

abstract class IAdminAuthRepository {
  Future<void> resolveDeviceReset(String studentId, bool isApproved);
}

class FirebaseAdminAuthRepository implements IAdminAuthRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Approving frees both the student's account and their old phone (see DeviceBinding).
  @override
  Future<void> resolveDeviceReset(String studentId, bool isApproved) async {
    final userRef = _firestore.collection('users').doc(studentId);
    final batch = _firestore.batch();
    if (isApproved) {
      final deviceId =
          (await userRef.get()).data()?['registeredDeviceId']?.toString() ?? '';
      if (deviceId.isNotEmpty) {
        batch.delete(_firestore.collection('devices').doc(deviceId));
      }
    }
    batch.set(userRef, {
      if (isApproved) 'registeredDeviceId': '',
      'deviceResetStatus': isApproved ? 'approved' : 'rejected',
      'deviceResetResolvedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }
}
