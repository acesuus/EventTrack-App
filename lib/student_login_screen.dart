import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'student_consent_screen.dart';
import 'student_dashboard.dart';

class StudentLoginScreen extends StatefulWidget {
  const StudentLoginScreen({super.key});

  @override
  State<StudentLoginScreen> createState() => _StudentLoginScreenState();
}

class _StudentLoginScreenState extends State<StudentLoginScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Controllers for the new UI fields
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  // Theme Colors from your mockup
  final Color _primaryGreen = const Color(0xFF28A776);
  final Color _lightGreenBg = const Color(0xFFEAF9F1);
  final Color _darkText = const Color(0xFF0C2D48);

  // 🚨 SECURITY: Fetch Hardware ID
  Future<String?> _getDeviceId() async {
    if (kIsWeb) return 'web_test_device_id';
    var deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isIOS) {
        var iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor;
      } else if (Platform.isAndroid) {
        var androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id;
      }
    } catch (e) {
      debugPrint("Failed to get device ID: $e");
    }
    return null;
  }

  // Login Logic (UI + Security Integration)
  Future<void> _handleLogin() async {
    String emailOrId = _emailController.text.trim();
    String password = _passwordController.text.trim();

    if (emailOrId.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter both Email/ID and Password'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String studentId = emailOrId.split('@')[0];
      String? currentDeviceId = await _getDeviceId();
      if (currentDeviceId == null) {
        throw Exception("Could not verify secure device ID.");
      }

      // 1. CLOUD DEVICE GATEKEEPER: Check if this phone is already owned by someone else
      final deviceCheck = await _firestore.collection('users')
          .where('registeredDeviceId', isEqualTo: currentDeviceId)
          .get(const GetOptions(source: Source.server));

      if (deviceCheck.docs.isNotEmpty) {
        final ownerId = deviceCheck.docs.first.id;
        if (ownerId != studentId) {
          // BLOCK LOGIN: This physical phone belongs to a different student ID
          if (!mounted) return;
          _showSecurityAlert(); // Shows the "Account Proxy Detected" dialog
          return;
        }
      }

      DocumentReference userRef = _firestore.collection('users').doc(studentId);
      DocumentSnapshot userSnap = await userRef.get(const GetOptions(source: Source.server));

      if (!userSnap.exists) {
        // First time registration: Bind this device to this new account
        await userRef.set({
          'studentId': studentId,
          'email': emailOrId,
          'name': 'Student $studentId',
          'registeredDeviceId': currentDeviceId,
          'hasConsented': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        await _saveLoginSession(studentId, 'Student $studentId', false);
        _navigateAfterLogin(studentId, 'Student $studentId', false);
      } else {
        // Returning user check
        Map<String, dynamic> userData = userSnap.data() as Map<String, dynamic>;
        String? registeredDevice = userData['registeredDeviceId'];
        final hasConsented = userData['hasConsented'] == true;
        final studentName = userData['name'] ?? 'Student';

        if (registeredDevice == null || registeredDevice.isEmpty) {
          // Claim the device if the account has no bound ID yet
          await userRef.update({'registeredDeviceId': currentDeviceId});
          await _saveLoginSession(studentId, studentName, hasConsented);
          _navigateAfterLogin(studentId, studentName, hasConsented);
        } else if (registeredDevice != currentDeviceId) {
          // Block if the account is trying to log in from an unauthorized phone
          if (!mounted) return;
          _showSecurityAlert();
        } else {
          // Standard authorized login
          await _saveLoginSession(studentId, studentName, hasConsented);
          _navigateAfterLogin(studentId, studentName, hasConsented);
        }
      }
    } catch (e) {
      if (!mounted) return;
      
      String cleanMessage = 'An unexpected error occurred. Please try again.';
      final errorStr = e.toString();

      if (errorStr.contains('SECURITY_VIOLATION')) {
        cleanMessage = errorStr.replaceAll('Exception: ', '');
      } else if (errorStr.contains('network-request-failed') || errorStr.contains('SocketException') || errorStr.contains('unavailable')) {
        cleanMessage = 'Network error. Please check your internet connection.';
      } else if (errorStr.contains('user-not-found') || errorStr.contains('wrong-password') || errorStr.contains('INVALID_LOGIN')) {
        cleanMessage = 'Invalid student credentials. Please verify your ID.';
      } else {
        cleanMessage = 'Login failed. Please try again later.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(cleanMessage),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveLoginSession(
    String studentId,
    String name,
    bool hasConsented,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('studentId', studentId);
    await prefs.setString('studentName', name);
    await prefs.setBool('hasConsented', hasConsented);
  }

  void _showSecurityAlert() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.gpp_bad, color: Colors.red),
            SizedBox(width: 8),
            Text('Security Alert', style: TextStyle(color: Colors.red)),
          ],
        ),
        content: const Text(
          'Account Proxy Detected.\n\nThis account is already registered to another physical device. You cannot log in from a different phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _navigateAfterLogin(String id, String name, bool hasConsented) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => hasConsented
            ? StudentDashboardScreen(studentId: id, studentName: name)
            : StudentConsentScreen(studentId: id, studentName: name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightGreenBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Logo & Headers
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _primaryGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.school, color: Colors.white, size: 50),
              ),
              const SizedBox(height: 24),
              Text(
                'Event Track',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: _darkText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Palawan State University',
                style: TextStyle(fontSize: 14, color: _primaryGreen),
              ),
              const SizedBox(height: 40),

              // Login Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Student Login',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _darkText,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Email Field
                    Text(
                      'Student Email or ID',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _darkText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'student@psu.palawan.edu.ph',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(
                          Icons.mail_outline,
                          color: Colors.grey.shade400,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _primaryGreen,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Password Field
                    Text(
                      'Password',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _darkText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        hintText: 'Enter your password',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(
                          Icons.lock_outline,
                          color: Colors.grey.shade400,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.grey.shade400,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _primaryGreen,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Login Button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _handleLogin,
                        icon: _isLoading
                            ? const SizedBox.shrink()
                            : const Icon(
                                Icons.person_outline,
                                color: Colors.white,
                              ),
                        label: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Login as Student',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryGreen,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Forgot Password
                    Center(
                      child: TextButton(
                        onPressed:
                            () {}, // Add password reset logic later if needed
                        child: Text(
                          'Forgot Password?',
                          style: TextStyle(
                            color: _primaryGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
