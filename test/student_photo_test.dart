import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:event_track/student_photo.dart';
import 'package:event_track/widgets/eventtrack_brand.dart';
import 'package:event_track/widgets/student_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('profile preparation crops a wide image to a bounded square', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, 500, 250),
        ui.Paint()..color = Colors.red,
      );
      canvas.drawRect(
        const ui.Rect.fromLTWH(125, 0, 250, 250),
        ui.Paint()..color = Colors.green,
      );
      final picture = recorder.endRecording();
      final source = await picture.toImage(500, 250);
      picture.dispose();
      final input = await source.toByteData(format: ui.ImageByteFormat.png);
      source.dispose();
      final encoded = await StudentPhoto.prepare(input!.buffer.asUint8List());
      final bytes = base64Decode(encoded);
      expect(bytes.length, lessThanOrEqualTo(StudentPhoto.maxThumbnailBytes));
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      expect(image.width, image.height);
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      // Center-cropping removes the red side bands and keeps the green subject.
      final sample = ((image.height ~/ 2) * image.width + image.width ~/ 8) * 4;
      expect(pixels!.getUint8(sample), closeTo(Colors.green.r * 255, 1));
      expect(pixels.getUint8(sample + 1), closeTo(Colors.green.g * 255, 1));
      image.dispose();
      codec.dispose();
    });
  });

  test('empty and oversized photo files are rejected', () async {
    await expectLater(
      StudentPhoto.prepare(Uint8List(0)),
      throwsFormatException,
    );
    await expectLater(
      StudentPhoto.prepare(Uint8List(StudentPhoto.maxSourceBytes + 1)),
      throwsFormatException,
    );
  });

  testWidgets('missing or malformed photos fall back to student initials', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: StudentAvatar(name: 'Juan Dela Cruz', photoBase64: 'not@base64'),
      ),
    );
    expect(find.text('JD'), findsOneWidget);
    await tester.pumpWidget(
      const MaterialApp(home: StudentAvatar(name: 'Kert Updated')),
    );
    expect(find.text('KU'), findsOneWidget);
    expect(find.text('JD'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Campus Pin asset loads in a compact branded header', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox(width: 160, child: EventTrackBrand())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('EventTrack'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
