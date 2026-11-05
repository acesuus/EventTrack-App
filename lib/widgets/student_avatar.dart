import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'student_ui.dart';

class StudentAvatar extends StatefulWidget {
  const StudentAvatar({
    super.key,
    required this.name,
    this.photoBase64,
    this.size = 56,
    this.background = StudentUi.green,
    this.foreground = Colors.white,
  });
  final String name;
  final String? photoBase64;
  final double size;
  final Color background;
  final Color foreground;

  @override
  State<StudentAvatar> createState() => _StudentAvatarState();
}

class _StudentAvatarState extends State<StudentAvatar> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(StudentAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoBase64 != widget.photoBase64) _decode();
  }

  void _decode() {
    try {
      final value = widget.photoBase64;
      _bytes = value == null || value.isEmpty || value.length > 200000
          ? null
          : base64Decode(value);
    } catch (_) {
      _bytes = null;
    }
  }

  Widget _fallback() {
    final words = widget.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty);
    final initials = words.isEmpty
        ? 'S'
        : words
              .take(2)
              .map((part) => part.characters.first.toUpperCase())
              .join();
    return ColoredBox(
      color: widget.background,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(widget.size * 0.18),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              initials,
              style: TextStyle(
                color: widget.foreground,
                fontSize: widget.size * 0.36,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: '${widget.name} profile photo',
    excludeSemantics: true,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(widget.size * 0.26),
      child: SizedBox.square(
        dimension: widget.size,
        child: _bytes == null
            ? _fallback()
            : Image.memory(
                _bytes!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _fallback(),
              ),
      ),
    ),
  );
}
