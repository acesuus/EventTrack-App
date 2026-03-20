import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter both Email/ID and Password')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // In a real app, you would use FirebaseAuth here.
      // For this prototype, we simulate a successful login if fields aren't empty, 
      // and use the email prefix as the "Student ID" for the database.
      String studentId = emailOrId.split('@')[0]; 
      
      String? currentDeviceId = await _getDeviceId();
      if (currentDeviceId == null) throw Exception("Could not verify secure device ID.");

      DocumentReference userRef = _firestore.collection('users').doc(studentId);
      DocumentSnapshot userSnap = await userRef.get();

      if (!userSnap.exists) {
        // First time: Register and Bind Device
        await userRef.set({
          'studentId': studentId,
          'email': emailOrId,
          'name': 'Student $studentId',
          'registeredDeviceId': currentDeviceId,
          'hasConsented': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        await _saveLoginSession(studentId, 'Student $studentId');
        _navigateToDashboard(studentId, 'Student $studentId');
      } else {
        // Returning Student: Verify Device Binding
        Map<String, dynamic> userData = userSnap.data() as Map<String, dynamic>;
        String? registeredDevice = userData['registeredDeviceId'];

        if (registeredDevice == null) {
          await userRef.update({'registeredDeviceId': currentDeviceId});
          await _saveLoginSession(studentId, userData['name'] ?? 'Student');
          _navigateToDashboard(studentId, userData['name'] ?? 'Student');
        } else if (registeredDevice != currentDeviceId) {
          // FRAUD DETECTED
          if (!mounted) return;
          _showSecurityAlert();
        } else {
          // Valid Login
          await _saveLoginSession(studentId, userData['name'] ?? 'Student');
          _navigateToDashboard(studentId, userData['name'] ?? 'Student');
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveLoginSession(String studentId, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('studentId', studentId);
    await prefs.setString('studentName', name);
  }

  void _showSecurityAlert() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.gpp_bad, color: Colors.red),
            SizedBox(width: 8),
            Text('Security Alert', style: TextStyle(color: Colors.red)),
          ],
        ),
        content: const Text('Account Proxy Detected.\n\nThis account is already registered to another physical device. You cannot log in from a different phone.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _navigateToDashboard(String id, String name) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => StudentDashboardScreen(studentId: id, studentName: name)),
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
                decoration: BoxDecoration(color: _primaryGreen, shape: BoxShape.circle),
                child: const Icon(Icons.school, color: Colors.white, size: 50),
              ),
              const SizedBox(height: 24),
              Text('Event Track', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: _darkText)),
              const SizedBox(height: 8),
              Text('Palawan State University', style: TextStyle(fontSize: 14, color: _primaryGreen)),
              const SizedBox(height: 40),
              
              // Login Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 5))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Student Login', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _darkText)),
                    const SizedBox(height: 24),

                    // Email Field
                    Text('Student Email or ID', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _darkText)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'student@psu.palawan.edu.ph',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                        prefixIcon: Icon(Icons.mail_outline, color: Colors.grey.shade400),
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _primaryGreen, width: 2)),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Password Field
                    Text('Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _darkText)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        hintText: 'Enter your password',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                        prefixIcon: Icon(Icons.lock_outline, color: Colors.grey.shade400),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey.shade400),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _primaryGreen, width: 2)),
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
                            : const Icon(Icons.person_outline, color: Colors.white),
                        label: _isLoading 
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Login as Student', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryGreen,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Forgot Password
                    Center(
                      child: TextButton(
                        onPressed: () {}, // Add password reset logic later if needed
                        child: Text('Forgot Password?', style: TextStyle(color: _primaryGreen, fontWeight: FontWeight.w600)),
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