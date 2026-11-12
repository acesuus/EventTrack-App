import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../attendance_policy.dart';

abstract class IEventRepository {
  Stream<List<Map<String, dynamic>>> getActiveEventsStream();
  Future<void> createEvent(Map<String, dynamic> eventData);
  Future<void> updateEvent(String eventId, Map<String, dynamic> eventData);
  Future<void> deleteEvent(String eventId);
  Future<void> executeManualFallbackCheckIn(String eventId, String studentId);
}

class FirebaseEventRepository implements IEventRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collectionPath = 'events';

  @override
  Stream<List<Map<String, dynamic>>> getActiveEventsStream() {
    return _firestore
        .collection(_collectionPath)
        .orderBy('startTime', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();
        });
  }

  @override
  Future<void> createEvent(Map<String, dynamic> eventData) async {
    eventData['createdAt'] = FieldValue.serverTimestamp();
    await _firestore.collection(_collectionPath).add(eventData);
  }

  @override
  Future<void> updateEvent(
    String eventId,
    Map<String, dynamic> eventData,
  ) async {
    await _firestore.collection(_collectionPath).doc(eventId).update(eventData);
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    await _firestore.collection(_collectionPath).doc(eventId).delete();
  }

  /// Admin override when a student can't check in by GPS (dead phone, bad signal).
  /// Marks them Present with full points and records who did it.
  @override
  Future<void> executeManualFallbackCheckIn(
    String eventId,
    String studentId,
  ) async {
    final event =
        (await _firestore.collection(_collectionPath).doc(eventId).get())
            .data();
    if (event == null) throw StateError('This event no longer exists.');
    final ref = _firestore
        .collection('attendance')
        .doc('${studentId}_$eventId');
    final existing = (await ref.get()).data();
    final now = Timestamp.now();
    final start = event['startTime'] as Timestamp? ?? now;
    final end = event['endTime'] as Timestamp? ?? now;
    final timeIn = existing?['timeIn'] as Timestamp? ?? start;
    final title = (event['title'] ?? '').toString().trim();
    await ref.set({
      'schemaVersion': AttendancePolicy.schemaVersion,
      'studentId': studentId,
      'eventId': eventId,
      'eventTitle': title,
      'eventName': title,
      'eventType': event['eventType'] ?? AttendancePolicy.eventTypeContinuous,
      'initialStatus': 'Present',
      'status': 'Present',
      'timeIn': timeIn,
      // Finished now, so the student's phone won't change it afterwards.
      'timeOut': existing?['timeOut'] ?? (now.compareTo(end) < 0 ? now : end),
      if (existing == null) ...{
        'totalOutsideSeconds': 0,
        'sessions': [
          {'timeIn': timeIn, 'timeOut': now.compareTo(end) < 0 ? now : end},
        ],
      },
      'pointsAwarded': AttendancePolicy.pointsFor(
        'Present',
        AttendancePolicy.basePointsOf(event),
      ),
      'manualOverride': true,
      if (existing != null) 'statusBeforeOverride': existing['status'],
      'overriddenBy': FirebaseAuth.instance.currentUser?.uid,
      'overriddenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
