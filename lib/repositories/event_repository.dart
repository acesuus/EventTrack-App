import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  Future<void> updateEvent(String eventId, Map<String, dynamic> eventData) async {
    await _firestore.collection(_collectionPath).doc(eventId).update(eventData);
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    await _firestore.collection(_collectionPath).doc(eventId).delete();
  }

  @override
  Future<void> executeManualFallbackCheckIn(String eventId, String studentId) async {
    final docId = '${studentId}_$eventId';
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    await _firestore.collection('attendance').doc(docId).set({
      'eventId': eventId,
      'studentId': studentId,
      'status': 'Present (Manual)',
      'timeIn': FieldValue.serverTimestamp(),
      'overriddenBy': currentUserId,
      'geofenceBypassed': true,
    }, SetOptions(merge: true));
  }
}
