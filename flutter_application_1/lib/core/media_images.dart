import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

Future<Uint8List> prepareImage(
  Uint8List bytes, {
  double? aspectRatio,
  int turns = 0,
}) async {
  final codec = await ui.instantiateImageCodec(bytes);
  var image = (await codec.getNextFrame()).image;
  codec.dispose();
  try {
    if (turns % 4 != 0) {
      final rotatedWidth = turns.isOdd ? image.height : image.width;
      final rotatedHeight = turns.isOdd ? image.width : image.height;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      if (turns == 1) canvas.translate(rotatedWidth.toDouble(), 0);
      if (turns == 2) {
        canvas.translate(rotatedWidth.toDouble(), rotatedHeight.toDouble());
      }
      if (turns == 3) canvas.translate(0, rotatedHeight.toDouble());
      canvas.rotate(turns * math.pi / 2);
      canvas.drawImage(image, Offset.zero, Paint());
      final picture = recorder.endRecording();
      final rotated = await picture.toImage(rotatedWidth, rotatedHeight);
      picture.dispose();
      image.dispose();
      image = rotated;
    }
    final ratio = aspectRatio ?? image.width / image.height;
    final width = math.min(1080, image.width).toInt();
    final height = (width / ratio).round().clamp(1, 1920);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final sourceSize = Size(image.width.toDouble(), image.height.toDouble());
    final targetSize = Size(width.toDouble(), height.toDouble());
    final fitted = applyBoxFit(BoxFit.cover, sourceSize, targetSize);
    canvas.drawImageRect(
      image,
      Alignment.center.inscribe(fitted.source, Offset.zero & sourceSize),
      Offset.zero & targetSize,
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final result = await picture.toImage(width, height);
    picture.dispose();
    try {
      return (await result.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
    } finally {
      result.dispose();
    }
  } finally {
    image.dispose();
  }
}

Future<Uint8List> imageCollage(List<Uint8List> bytes) async {
  final images = <ui.Image>[];
  try {
    for (final data in bytes.take(4)) {
      final codec = await ui.instantiateImageCodec(data);
      try {
        images.add((await codec.getNextFrame()).image);
      } finally {
        codec.dispose();
      }
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    for (var i = 0; i < images.length; i++) {
      final image = images[i];
      final columns = images.length == 1 ? 1 : 2;
      final rows = images.length <= 2 ? 1 : 2;
      final box = Rect.fromLTWH(
        (i % columns) * 1080 / columns + 4,
        (i ~/ columns) * 1080 / rows + 4,
        1080 / columns - 8,
        1080 / rows - 8,
      );
      final sourceSize = Size(image.width.toDouble(), image.height.toDouble());
      final fitted = applyBoxFit(BoxFit.cover, sourceSize, box.size);
      canvas.drawImageRect(
        image,
        Alignment.center.inscribe(fitted.source, Offset.zero & sourceSize),
        box,
        Paint()..filterQuality = FilterQuality.high,
      );
    }
    final picture = recorder.endRecording();
    final result = await picture.toImage(1080, 1080);
    picture.dispose();
    try {
      return (await result.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
    } finally {
      result.dispose();
    }
  } finally {
    for (final image in images) {
      image.dispose();
    }
  }
}
