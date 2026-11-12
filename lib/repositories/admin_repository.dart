import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

abstract class IAdminEventRepository {
  Future<void> resolveAttendanceAppeal(String recordId, bool isApproved);
}

class FirebaseAdminEventRepository implements IAdminEventRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Future<void> resolveAttendanceAppeal(String recordId, bool isApproved) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (isApproved) {
      await _firestore.collection('attendance').doc(recordId).update({
        'status': 'Present (Appealed)',
        'appealStatus': 'approved',
        'resolvedBy': currentUserId,
      });
    } else {
      await _firestore.collection('attendance').doc(recordId).update({
        'appealStatus': 'rejected',
        'resolvedBy': currentUserId,
      });
    }
  }
}
