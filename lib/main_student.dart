import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'student_login_screen.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'student_dashboard.dart';
import 'student_consent_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final prefs = await SharedPreferences.getInstance();
  final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
  final studentId = prefs.getString('studentId') ?? '';
  final studentName = prefs.getString('studentName') ?? 'Student';
  final hasConsented = prefs.getBool('hasConsented') ?? false;

  runApp(
    MaterialApp(
      title: 'EventTrack Student',
      home: isLoggedIn
          ? (hasConsented
                ? StudentDashboardScreen(
                    studentId: studentId,
                    studentName: studentName,
                  )
                : StudentConsentScreen(
                    studentId: studentId,
                    studentName: studentName,
                  ))
          : const StudentLoginScreen(),
      debugShowCheckedModeBanner: false,
    ),
  );
}
