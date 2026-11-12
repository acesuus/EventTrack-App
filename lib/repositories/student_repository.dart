import 'package:cloud_firestore/cloud_firestore.dart';

abstract class IStudentEventRepository {
  Future<void> submitAttendanceAppeal(String recordId, String justification);
  Future<void> purgeLocationTelemetry(String recordId);
}

class FirebaseStudentEventRepository implements IStudentEventRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Future<void> submitAttendanceAppeal(String recordId, String justification) async {
    await _firestore.collection('attendance').doc(recordId).update({
      'appealStatus': 'pending',
      'appealReason': justification,
    });
  }

  @override
  Future<void> purgeLocationTelemetry(String recordId) async {
    await _firestore.collection('attendance').doc(recordId).update({
      'isTelemetryPurged': true,
      'distance_from_event': null,
    });
  }
}
