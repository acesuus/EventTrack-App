import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'student_dashboard.dart';

class StudentConsentScreen extends StatefulWidget {
  final String studentId; // Passed in after login
  final String studentName;

  const StudentConsentScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<StudentConsentScreen> createState() => _StudentConsentScreenState();
}

class _StudentConsentScreenState extends State<StudentConsentScreen> {
  bool _isAgreed = false;
  final Color _primaryGreen = const Color(0xFF28A776);

  Future<void> _requestPermissions() async {
    if (!_isAgreed) return;

    // 1. Check OS permissions
    // 1. Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled && !kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location services are disabled. Please enable them.')),
      );
      return;
    }

    // 2. Check and request permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // This will trigger the browser's permission pop-up on Web
      permission = await Geolocator.requestPermission();
    }

    // 3. The Web Workaround & Strict OS Checks
    if (kIsWeb) {
      // Proceed to next screen and let the browser/sensors handle the data
    } else {
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required for attendance.')),
        );
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permissions are permanently denied. Please enable in settings.'),
          ),
        );
        return;
      }
    }

    // 4. Save Consent to Firestore
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.studentId)
        .set({
          'hasConsented': true,
          'consentDate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasConsented', true);

    // 3. Move to the tracking screen
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => StudentDashboardScreen(
          studentId: widget.studentId,
          studentName: widget.studentName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Privacy & Consent',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: _primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.privacy_tip_outlined,
              size: 60,
              color: Color(0xFF28A776),
            ),
            const SizedBox(height: 20),
            const Text(
              'How We Protect Your Data',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildPrivacyRule(
              Icons.location_off,
              'No 24/7 Tracking',
              'We only check your location when an event is actively happening.',
            ),
            _buildPrivacyRule(
              Icons.map,
              'No Real-Time Maps',
              'Admins cannot see where you are. They only see "Present" or "Absent".',
            ),
            _buildPrivacyRule(
              Icons.timer_off,
              'Auto-Deactivation',
              'GPS tracking stops the exact minute the event ends.',
            ),
            const Spacer(),
            Row(
              children: [
                Checkbox(
                  value: _isAgreed,
                  activeColor: _primaryGreen,
                  onChanged: (val) => setState(() => _isAgreed = val ?? false),
                ),
                const Expanded(
                  child: Text(
                    'I have read and agree to allow EventTrack to verify my location for attendance.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isAgreed ? _requestPermissions : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryGreen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Grant Permission & Continue',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyRule(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _primaryGreen, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(desc, style: TextStyle(color: Colors.grey.shade700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
