import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'admin_auth_screen.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  runApp(const MaterialApp(
    title: 'EventTrack Admin',
    home: AdminAuthGate(),
    debugShowCheckedModeBanner: false,
  ));
}
