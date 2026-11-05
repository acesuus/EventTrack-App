import 'package:flutter/material.dart';

import 'student_ui.dart';

class EventTrackMark extends StatelessWidget {
  const EventTrackMark({
    super.key,
    this.size = 36,
    this.color = StudentUi.green,
  });
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/branding/campus_pin_mark.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    color: color,
    colorBlendMode: BlendMode.srcIn,
    semanticLabel: 'EventTrack',
  );
}

class EventTrackBrand extends StatelessWidget {
  const EventTrackBrand({
    super.key,
    this.color = StudentUi.green,
    this.size = 28,
  });
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ExcludeSemantics(
        child: EventTrackMark(size: size, color: color),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          'EventTrack',
          style: TextStyle(
            color: color,
            fontSize: size * 0.65,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
      ),
    ],
  );
}
