import 'package:cloud_firestore/cloud_firestore.dart';

abstract class IAdminAuthRepository {
  Future<void> resolveDeviceReset(String studentId, bool isApproved);
}

class FirebaseAdminAuthRepository implements IAdminAuthRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Future<void> resolveDeviceReset(String studentId, bool isApproved) async {
    final Map<String, dynamic> updateData = {};
    
    if (isApproved) {
      updateData['deviceResetStatus'] = 'none';
      updateData['registeredDeviceId'] = FieldValue.delete();
    } else {
      updateData['deviceResetStatus'] = 'rejected';
    }

    await _firestore.collection('users').doc(studentId).update(updateData);
  }
}
