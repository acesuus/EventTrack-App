import 'package:cloud_firestore/cloud_firestore.dart';

abstract class IStudentEventRepository {
  Future<void> submitAttendanceAppeal(String recordId, String justification);
}

class FirebaseStudentEventRepository implements IStudentEventRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Firestore rules only let a student set these three fields, once per record.
  @override
  Future<void> submitAttendanceAppeal(String recordId, String justification) =>
      _firestore.collection('attendance').doc(recordId).update({
        'appealStatus': 'pending',
        'appealReason': justification,
        'appealedAt': FieldValue.serverTimestamp(),
      });
}
