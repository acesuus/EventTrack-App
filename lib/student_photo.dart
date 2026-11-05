import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Produces a small square profile image without uploading the full-size file.
class StudentPhoto {
  static const maxSourceBytes = 12 * 1024 * 1024;
  static const maxThumbnailBytes = 120 * 1024;

  static Future<String> prepare(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxSourceBytes) {
      throw const FormatException('Choose an image smaller than 12 MB.');
    }
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 768,
      allowUpscaling: false,
    );
    ui.Image? source;
    try {
      source = (await codec.getNextFrame()).image;
      final side = source.width < source.height ? source.width : source.height;
      final crop = ui.Rect.fromLTWH(
        (source.width - side) / 2,
        (source.height - side) / 2,
        side.toDouble(),
        side.toDouble(),
      );
      for (final size in [384, 256, 192, 128]) {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawImageRect(
          source,
          crop,
          ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
          ui.Paint()..filterQuality = ui.FilterQuality.high,
        );
        final picture = recorder.endRecording();
        final thumbnail = await picture.toImage(size, size);
        picture.dispose();
        try {
          final data = await thumbnail.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (data != null && data.lengthInBytes <= maxThumbnailBytes) {
            return base64Encode(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            );
          }
        } finally {
          thumbnail.dispose();
        }
      }
      throw const FormatException(
        'This image could not be resized. Choose another photo.',
      );
    } finally {
      source?.dispose();
      codec.dispose();
    }
  }
}
