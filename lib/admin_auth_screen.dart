import 'widgets/eventtrack_brand.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_dashboard.dart';

class AdminAuthGate extends StatelessWidget {
  const AdminAuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, session) {
        if (session.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = session.data;
        if (user == null) return const AdminLoginScreen();
        return FutureBuilder<IdTokenResult>(
          future: user.getIdTokenResult(true),
          builder: (context, token) {
            if (token.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (!token.hasError && token.data?.claims?['admin'] == true) {
              return const AdminDashboardScreen();
            }
            return Scaffold(
              appBar: AppBar(title: const Text('Administrator access')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        token.hasError
                            ? 'Could not verify access. Check your connection and sign in again.'
                            : 'This account does not have administrator access.',
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => FirebaseAuth.instance.signOut(),
                        child: const Text('Return to sign in'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  static const _primaryGreen = Color(0xFF1E7F5A);
  static const _lightGreenBg = Color(0xFFEAF9F1);
  static const _darkText = Color(0xFF0C2D48);
  static const _demoEmail = String.fromEnvironment('ADMIN_DEMO_EMAIL');
  static const _demoPassword = String.fromEnvironment('ADMIN_DEMO_PASSWORD');
  bool _obscurePassword = true;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit({bool resetPassword = false}) async {
    if (_busy) {
      return;
    }
    if (resetPassword
        ? !_email.text.contains('@')
        : !_form.currentState!.validate()) {
      setState(() => _message = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (resetPassword) {
        await FirebaseAuth.instance.sendPasswordResetEmail(
          email: _email.text.trim(),
        );
        if (mounted) {
          setState(
            () => _message =
                'If this account exists, a password reset email has been sent.',
          );
        }
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(
          () => _message = switch (error.code) {
            'network-request-failed' =>
              'Check your internet connection and try again.',
            'too-many-requests' => 'Too many attempts. Please try again later.',
            'operation-not-allowed' =>
              'Email/password sign-in is not enabled. Contact the project owner.',
            _ =>
              'Unable to sign in. Check your email and password and try again.',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Unable to connect. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _inputDecoration(
    String hint,
    IconData icon, {
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
      prefixIcon: Icon(icon, color: Colors.grey.shade600),
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primaryGreen, width: 2),
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: _darkText,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _lightGreenBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const EventTrackMark(size: 90),
                  const SizedBox(height: 24),
                  const Text(
                    'EventTrack',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: _darkText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
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
                    child: AutofillGroup(
                      child: Form(
                        key: _form,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Admin Login',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: _darkText,
                              ),
                            ),
                            if (_demoEmail.isNotEmpty &&
                                _demoPassword.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _lightGreenBg,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: _primaryGreen.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Administrator account',
                                      style: TextStyle(
                                        color: _primaryGreen,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    SelectableText(
                                      _demoEmail,
                                      style: TextStyle(
                                        color: _darkText,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    SelectableText(
                                      'Password: $_demoPassword',
                                      style: TextStyle(
                                        color: _darkText,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            _fieldLabel('Admin Email'),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _email,
                              enabled: !_busy,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.username],
                              autocorrect: false,
                              decoration: _inputDecoration(
                                _demoEmail.isNotEmpty
                                    ? _demoEmail
                                    : 'Enter your admin email',
                                Icons.mail_outline,
                              ),
                              validator: (value) =>
                                  value != null && value.trim().contains('@')
                                  ? null
                                  : 'Enter your email.',
                            ),
                            const SizedBox(height: 20),
                            _fieldLabel('Password'),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _password,
                              enabled: !_busy,
                              obscureText: _obscurePassword,
                              autofillHints: const [AutofillHints.password],
                              textInputAction: TextInputAction.done,
                              decoration: _inputDecoration(
                                'Enter your password',
                                Icons.lock_outline,
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
                                  onPressed: _busy
                                      ? null
                                      : () => setState(
                                          () => _obscurePassword =
                                              !_obscurePassword,
                                        ),
                                ),
                              ),
                              validator: (value) =>
                                  value == null || value.isEmpty
                                  ? 'Enter your password.'
                                  : null,
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            if (_message != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    _message!,
                                    key: const Key('auth-message'),
                                    style: const TextStyle(color: _darkText),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton.icon(
                                onPressed: _busy ? null : () => _submit(),
                                icon: _busy
                                    ? const SizedBox.shrink()
                                    : const Icon(
                                        Icons.admin_panel_settings_outlined,
                                        color: Colors.white,
                                      ),
                                label: _busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text(
                                        'Login as Admin',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryGreen,
                                  disabledBackgroundColor: _primaryGreen
                                      .withValues(alpha: 0.6),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _submit(resetPassword: true),
                                child: const Text(
                                  'Set or reset password',
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
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
