import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../attendance_policy.dart';

abstract class IAdminEventRepository {
  Future<void> resolveAttendanceAppeal(String recordId, bool isApproved);
}

class FirebaseAdminEventRepository implements IAdminEventRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// An approved appeal counts as Present, with the event's full points.
  @override
  Future<void> resolveAttendanceAppeal(String recordId, bool isApproved) async {
    final ref = _firestore.collection('attendance').doc(recordId);
    final update = <String, dynamic>{
      'appealStatus': isApproved ? 'approved' : 'rejected',
      'appealResolvedBy': FirebaseAuth.instance.currentUser?.uid,
      'appealResolvedAt': FieldValue.serverTimestamp(),
    };
    if (isApproved) {
      final record = (await ref.get()).data() ?? {};
      final event =
          (await _firestore
                  .collection('events')
                  .doc(record['eventId']?.toString())
                  .get())
              .data() ??
          {};
      update['statusBeforeAppeal'] = record['status'];
      update['status'] = 'Present';
      update['pointsAwarded'] = AttendancePolicy.pointsFor(
        'Present',
        AttendancePolicy.basePointsOf(event),
      );
    }
    await ref.update(update);
  }
}
