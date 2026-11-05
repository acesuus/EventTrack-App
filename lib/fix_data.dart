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

  final snapshot = await firestore.collection('events').where('title', isEqualTo: 'Test Mock Event').get();
  for (var doc in snapshot.docs) {
    await doc.reference.update({
      'eventType': 'type2_continuous', // Valid type
    });
  }

  print("====== FIX COMPLETE! ======");

  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Fix Complete! You can close this and run the app normally.'),
        ),
      ),
    ),
  );
}
