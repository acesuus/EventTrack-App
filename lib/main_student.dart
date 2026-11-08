import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'student_consent_screen.dart';
import 'student_dashboard.dart';
import 'student_login_screen.dart';
import 'widgets/student_ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Step 2: Enable Firebase Offline Persistence
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  final prefs = await SharedPreferences.getInstance();
  final studentId = prefs.getString('studentId') ?? '';
  // Sessions from before student sign-in existed have no Firebase user: log in again.
  final user = await FirebaseAuth.instance.authStateChanges().first;
  final isLoggedIn =
      (prefs.getBool('isLoggedIn') ?? false) &&
      studentId.isNotEmpty &&
      user != null &&
      user.emailVerified;
  final studentName = prefs.getString('studentName') ?? 'Student';
  final hasConsented = prefs.getBool('hasConsented') ?? false;

  runApp(
    MaterialApp(
      title: 'EventTrack Student',
      theme: StudentUi.theme,
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
