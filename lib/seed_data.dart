import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final firestore = FirebaseFirestore.instance;

  // 1. Create a dummy event
  final eventRef = await firestore.collection('events').add({
    'title': 'Test Mock Event',
    'description': 'A mock event for testing',
    'venueName': 'Main Campus',
    'venueAddress': 'Campus Address',
    'lat': 16.03,
    'lng': 120.33,
    'polygonPoints': [],
    'lateCutoffMinutes': 15,
    'eventType': 'Standard',
    'basePoints': 10,
    'startTime': Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 1))),
    'endTime': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 1))),
    'createdAt': FieldValue.serverTimestamp(),
  });

  final eventId = eventRef.id;

  // 2. Add students
  final students = [
    {'id': '202380358', 'name': 'Kert', 'year': '3rd', 'section': 'A'},
    {'id': '100000001', 'name': 'John Doe', 'year': '1st', 'section': 'A'},
    {'id': '100000002', 'name': 'Jane Smith', 'year': '2nd', 'section': 'B'},
    {'id': '100000003', 'name': 'Absent Student', 'year': '3rd', 'section': 'C'},
  ];

  for (var s in students) {
    await firestore.collection('students').doc(s['id']).set({
      'studentId': s['id'],
      'name': s['name'],
      'year': s['year'],
      'section': s['section'],
    });
  }

  // 3. Add attendance
  // Kert is Present with more points (e.g. 20)
  await firestore.collection('attendance').doc('202380358_$eventId').set({
    'studentId': '202380358',
    'eventId': eventId,
    'eventName': 'Test Mock Event',
    'eventTitle': 'Test Mock Event',
    'status': 'Present',
    'pointsAwarded': 20, // more points
    'timeIn': Timestamp.fromDate(DateTime.now()),
  });

  // John is Present
  await firestore.collection('attendance').doc('100000001_$eventId').set({
    'studentId': '100000001',
    'eventId': eventId,
    'eventName': 'Test Mock Event',
    'eventTitle': 'Test Mock Event',
    'status': 'Present',
    'pointsAwarded': 10,
    'timeIn': Timestamp.fromDate(DateTime.now()),
  });

  // Jane is Late
  await firestore.collection('attendance').doc('100000002_$eventId').set({
    'studentId': '100000002',
    'eventId': eventId,
    'eventName': 'Test Mock Event',
    'eventTitle': 'Test Mock Event',
    'status': 'Late',
    'pointsAwarded': 5,
    'timeIn': Timestamp.fromDate(DateTime.now()),
  });

  // Absent student gets nothing in attendance collection (they will be marked as absent by the export_utils)

  print("====== SEEDING COMPLETE! ======");

  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Seeding Complete! You can close this and run the app normally.'),
        ),
      ),
    ),
  );
}
