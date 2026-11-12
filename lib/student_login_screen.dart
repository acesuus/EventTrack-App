import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_binding.dart';
import 'repositories/student_auth_repository.dart';
import 'student_consent_screen.dart';
import 'student_dashboard.dart';
import 'student_profile.dart';
import 'widgets/eventtrack_brand.dart';

/// Students sign in with their PSU student email.
/// First-time users activate an account, verify their email, then log in.
class StudentLoginScreen extends StatefulWidget {
  const StudentLoginScreen({super.key});

  @override
  State<StudentLoginScreen> createState() => _StudentLoginScreenState();
}

class _StudentLoginScreenState extends State<StudentLoginScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final IStudentAuthRepository _studentAuthRepo =
      FirebaseStudentAuthRepository();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isActivating = false;

  final Color _primaryGreen = const Color(0xFF1E7F5A);
  final Color _lightGreenBg = const Color(0xFFEAF9F1);
  final Color _darkText = const Color(0xFF0C2D48);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String get _email => _emailController.text.trim().toLowerCase();

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showInfo(String title, String message) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Email or password is incorrect. First time here? Tap "Activate your account".';
      case 'email-already-in-use':
        return 'This email already has an account. Log in instead, or reset your password.';
      case 'weak-password':
        return 'Use a password with at least 6 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Wait a few minutes and try again.';
      case 'network-request-failed':
        return 'No internet connection. Connect and try again.';
      default:
        return "Couldn't sign in. Please try again.";
    }
  }

  Future<void> _submit() async {
    if (_email.isEmpty || _passwordController.text.isEmpty) {
      _showMessage('Enter your email and password.');
      return;
    }
    if (studentIdFromEmail(_email) == null) {
      _showMessage(
        'Use your PSU email: your student ID (0000-0-0000) without dashes, then @psu.palawan.edu.ph.',
      );
      return;
    }
    if (_isActivating && _passwordController.text != _confirmController.text) {
      _showMessage('Passwords do not match.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      if (_isActivating) {
        await _activate();
      } else {
        await _login();
      }
    } on FirebaseAuthException catch (e) {
      _showMessage(_authErrorMessage(e));
    } catch (e) {
      debugPrint('Login failed: $e');
      _showMessage(
        "Couldn't log in. Check your internet connection and try again.",
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _activate() async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: _email,
      password: _passwordController.text,
    );
    await credential.user!.sendEmailVerification();
    await _auth.signOut();
    if (!mounted) return;
    setState(() {
      _isActivating = false;
      _confirmController.clear();
    });
    await _showInfo(
      'Verify your email',
      'We sent a verification link to $_email. Open it, then come back and log in.',
    );
  }

  Future<void> _login() async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: _email,
      password: _passwordController.text,
    );
    final user = credential.user!;
    if (!user.emailVerified) {
      await user.sendEmailVerification();
      await _auth.signOut();
      if (!mounted) return;
      await _showInfo(
        'Verify your email first',
        'We sent a new verification link to $_email. Open it, then log in again.',
      );
      return;
    }

    // The student ID comes from the email digits, in 0000-0-0000 format.
    final studentId = studentIdFromEmail(_email)!;
    // Optional: the admin's imported list may already have this student's details.
    var roster = <String, dynamic>{};
    try {
      roster =
          (await _firestore.collection('students').doc(studentId).get())
              .data() ??
          {};
    } on FirebaseException catch (e) {
      debugPrint('Student list lookup skipped: ${e.code}');
    }

    try {
      await DeviceBinding.bind(studentId);
    } on DeviceBindingException catch (e) {
      // Stay signed in until the dialog closes so a reset request can be saved.
      var resetStatus = 'none';
      if (e.canRequestReset) {
        try {
          resetStatus = await _studentAuthRepo.deviceResetStatus(studentId);
        } on FirebaseException catch (err) {
          debugPrint('Reset status lookup skipped: ${err.code}');
        }
      }
      if (mounted) {
        await _showSecurityAlert(
          e.message,
          studentId: e.canRequestReset ? studentId : null,
          resetPending: resetStatus == 'pending',
        );
      }
      await _auth.signOut();
      return;
    }

    final userData =
        (await _firestore.collection('users').doc(studentId).get()).data() ??
        {};
    final hasConsented = userData['hasConsented'] == true;
    final savedName = userData['name']?.toString().trim() ?? '';
    final rosterName = roster['name']?.toString().trim() ?? '';
    final name = savedName.isNotEmpty
        ? savedName
        : (rosterName.isNotEmpty ? rosterName : 'Student');
    // Fill empty profile fields from the imported list, never overwriting the student's own.
    final fill = <String, dynamic>{
      for (final key in ['name', 'program', 'yearBlock'])
        if ((userData[key]?.toString().trim() ?? '').isEmpty &&
            (roster[key]?.toString().trim() ?? '').isNotEmpty)
          key: roster[key],
    };
    if (fill.isNotEmpty) {
      try {
        await _firestore
            .collection('users')
            .doc(studentId)
            .set(fill, SetOptions(merge: true));
      } on FirebaseException catch (e) {
        debugPrint('Profile prefill skipped: ${e.code}');
      }
    }

    await _saveLoginSession(studentId, name, hasConsented);
    if (!mounted) return;
    _navigateAfterLogin(studentId, name, hasConsented);
  }

  Future<void> _resetPassword() async {
    if (_email.isEmpty) {
      _showMessage('Enter your email first, then tap "Forgot password?".');
      return;
    }
    try {
      await _auth.sendPasswordResetEmail(email: _email);
    } on FirebaseAuthException catch (e) {
      if (e.code != 'user-not-found') {
        _showMessage(_authErrorMessage(e));
        return;
      }
    }
    if (!mounted) return;
    await _showInfo(
      'Check your email',
      'If $_email has an account, we sent a link to reset the password.',
    );
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

  /// With [studentId], also offers to ask an admin to move the account to this phone.
  Future<void> _showSecurityAlert(
    String message, {
    String? studentId,
    bool resetPending = false,
  }) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.gpp_bad, color: Colors.red),
          SizedBox(width: 8),
          Text('Device not allowed', style: TextStyle(color: Colors.red)),
        ],
      ),
      content: Text(
        resetPending
            ? 'Your request to use this phone is waiting for admin approval. Try again later.'
            : message,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (studentId != null && !resetPending)
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _showDeviceResetDialog(studentId);
            },
            child: const Text('Request device reset'),
          ),
      ],
    ),
  );

  Future<void> _showDeviceResetDialog(String studentId) async {
    final reasonController = TextEditingController();
    var submitting = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Request device reset'),
          content: TextField(
            controller: reasonController,
            maxLines: 3,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'e.g. Lost phone, new phone, reinstalled the app',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final reason = reasonController.text.trim();
                      if (reason.isEmpty) return;
                      setDialogState(() => submitting = true);
                      try {
                        await _studentAuthRepo.requestDeviceReset(
                          studentId,
                          reason,
                        );
                        if (context.mounted) Navigator.pop(context);
                        _showMessage(
                          'Request sent. You can log in on this phone once an admin approves it.',
                        );
                      } catch (e) {
                        setDialogState(() => submitting = false);
                        _showMessage(
                          "Couldn't send the request. Check your connection.",
                        );
                      }
                    },
              child: const Text('Send request'),
            ),
          ],
        ),
      ),
    );
    reasonController.dispose();
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

  Widget _fieldLabel(String text) => ExcludeSemantics(
    // Visual label; the field below carries the same label for screen readers.
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: _darkText,
      ),
    ),
  );

  InputDecoration _decoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
    prefixIcon: Icon(icon, color: Colors.grey.shade600),
    suffixIcon: suffix,
    contentPadding: const EdgeInsets.symmetric(vertical: 16),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: _primaryGreen, width: 2),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightGreenBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const EventTrackMark(size: 90),
                const SizedBox(height: 24),
                Text(
                  'EventTrack',
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
                        _isActivating
                            ? 'Activate your account'
                            : 'Student Login',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _darkText,
                        ),
                      ),
                      if (_isActivating) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Use your PSU email: your student ID (0000-0-0000) without dashes, then @psu.palawan.edu.ph. Then choose a password.',
                        ),
                      ],
                      const SizedBox(height: 24),
                      _fieldLabel('PSU email'),
                      const SizedBox(height: 8),
                      Semantics(
                        label: 'PSU email',
                        child: TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                          decoration: _decoration(
                            hint: 'student-id@psu.palawan.edu.ph',
                            icon: Icons.mail_outline,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _fieldLabel('Password'),
                      const SizedBox(height: 8),
                      Semantics(
                        label: 'Password',
                        child: TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          autofillHints: [
                            _isActivating
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          textInputAction: _isActivating
                              ? TextInputAction.next
                              : TextInputAction.done,
                          onSubmitted: (_) {
                            if (!_isActivating && !_isLoading) _submit();
                          },
                          decoration: _decoration(
                            hint: _isActivating
                                ? 'At least 6 characters'
                                : 'Enter your password',
                            icon: Icons.lock_outline,
                            suffix: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.grey.shade600,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_isActivating) ...[
                        const SizedBox(height: 20),
                        _fieldLabel('Confirm password'),
                        const SizedBox(height: 8),
                        Semantics(
                          label: 'Confirm password',
                          child: TextField(
                            controller: _confirmController,
                            obscureText: _obscurePassword,
                            autofillHints: const [AutofillHints.newPassword],
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) {
                              if (!_isLoading) _submit();
                            },
                            decoration: _decoration(
                              hint: 'Type the password again',
                              icon: Icons.lock_outline,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryGreen,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _isActivating ? 'Create account' : 'Log in',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: _isLoading
                                ? null
                                : () => setState(() {
                                    _isActivating = !_isActivating;
                                    _confirmController.clear();
                                  }),
                            child: Text(
                              _isActivating
                                  ? 'Have an account? Log in'
                                  : 'Activate your account',
                            ),
                          ),
                          if (!_isActivating)
                            TextButton(
                              onPressed: _isLoading ? null : _resetPassword,
                              child: const Text('Forgot password?'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
