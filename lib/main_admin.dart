import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'admin_auth_screen.dart';
import 'firebase_options.dart';
import 'widgets/student_ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  runApp(MaterialApp(
    title: 'EventTrack Admin',
    theme: StudentUi.theme,
    home: const AdminAuthGate(),
    debugShowCheckedModeBanner: false,
  ));
}
