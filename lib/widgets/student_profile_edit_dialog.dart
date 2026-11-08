import 'package:flutter/material.dart';

import 'student_ui.dart';

class StudentProfileEditDialog extends StatefulWidget {
  const StudentProfileEditDialog({
    super.key,
    required this.name,
    required this.email,
    required this.studentId,
    required this.onSave,
  });

  final String name;
  final String email;
  final String studentId;
  final Future<void> Function(String name, String email) onSave;

  @override
  State<StudentProfileEditDialog> createState() =>
      _StudentProfileEditDialogState();
}

class _StudentProfileEditDialogState extends State<StudentProfileEditDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.name);
  late final _email = TextEditingController(text: widget.email);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_name.text.trim(), _email.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            'Could not save your profile. Check your connection and try again.';
      });
    }
  }

  InputDecoration _decoration(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 14, color: StudentUi.muted),
    prefixIcon: Icon(icon, size: 20, color: StudentUi.muted),
    filled: true,
    fillColor: const Color(0xFFF7FAF8),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: StudentUi.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: StudentUi.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: StudentUi.green, width: 2),
    ),
    errorMaxLines: 3,
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: StudentUi.ink,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.edit_outlined,
                            color: StudentUi.green,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Edit profile',
                              style: TextStyle(
                                color: StudentUi.ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: _saving
                                ? null
                                : () => Navigator.pop(context),
                            icon: const Icon(
                              Icons.close,
                              size: 20,
                              color: StudentUi.muted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Keep your name and contact details up to date.',
                        style: TextStyle(
                          color: StudentUi.muted,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Student ID',
                        style: TextStyle(color: StudentUi.muted, fontSize: 12),
                      ),
                      const SizedBox(height: 5),
                      SelectableText(
                        widget.studentId,
                        style: const TextStyle(
                          color: StudentUi.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Divider(height: 1, color: StudentUi.line),
                      ),
                      _label('Full name'),
                      TextFormField(
                        key: const Key('profile-name'),
                        controller: _name,
                        enabled: !_saving,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        decoration: _decoration(
                          'Enter your full name',
                          Icons.person_outline,
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter your full name.'
                            : null,
                      ),
                      const SizedBox(height: 20),
                      _label('School email'),
                      TextFormField(
                        key: const Key('profile-email'),
                        controller: _email,
                        enabled: !_saving,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                        decoration: _decoration(
                          'student-id@psu.palawan.edu.ph',
                          Icons.mail_outline,
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          return email.isEmpty ||
                                  RegExp(
                                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                  ).hasMatch(email)
                              ? null
                              : 'Enter a valid email address.';
                        },
                        onFieldSubmitted: (_) => _save(),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFFB23A3A),
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: StudentUi.line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: StudentUi.green,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: StudentUi.green,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    child: _saving
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  'Saving…',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          )
                        : const Text('Save changes'),
                  ),
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: StudentUi.muted,
                    ),
                    child: const Text('Cancel'),
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
