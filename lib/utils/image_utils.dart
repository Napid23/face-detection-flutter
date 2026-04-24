import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as img;

class ImageUtils {
  /// Konversi [CameraImage] (umumnya YUV420 di Android) menjadi [img.Image] RGB.
  static img.Image? cameraImageToImage(CameraImage cameraImage) {
    if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
      return _bgra8888ToImage(cameraImage);
    }

    if (cameraImage.format.group == ImageFormatGroup.yuv420) {
      return _yuv420ToImage(cameraImage);
    }

    return null;
  }

  static img.Image _bgra8888ToImage(CameraImage cameraImage) {
    final plane = cameraImage.planes.first;
    return img.Image.fromBytes(
      width: cameraImage.width,
      height: cameraImage.height,
      bytes: plane.bytes.buffer,
      rowStride: plane.bytesPerRow,
      order: img.ChannelOrder.bgra,
    );
  }

  static img.Image _yuv420ToImage(CameraImage cameraImage) {
    final int width = cameraImage.width;
    final int height = cameraImage.height;
    final img.Image image = img.Image(width: width, height: height);

    final planeY = cameraImage.planes[0];
    final planeU = cameraImage.planes[1];
    final planeV = cameraImage.planes[2];

    final int yRowStride = planeY.bytesPerRow;
    final int uvRowStride = planeU.bytesPerRow;
    final int uvPixelStride = planeU.bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      final int yRowOffset = yRowStride * y;
      final int uvRowOffset = uvRowStride * (y >> 1);

      for (int x = 0; x < width; x++) {
        final int yIndex = yRowOffset + x;
        final int uvIndex = uvRowOffset + (x >> 1) * uvPixelStride;

        final int yp = planeY.bytes[yIndex];
        final int up = planeU.bytes[uvIndex];
        final int vp = planeV.bytes[uvIndex];

        // YUV420 -> RGB (BT.601)
        final double yVal = yp.toDouble();
        final double uVal = (up - 128).toDouble();
        final double vVal = (vp - 128).toDouble();

        int r = (yVal + 1.402 * vVal).round();
        int g = (yVal - 0.344136 * uVal - 0.714136 * vVal).round();
        int b = (yVal + 1.772 * uVal).round();

        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        image.setPixelRgb(x, y, r, g, b);
      }
    }

    return image;
  }

  /// Rotasi [img.Image] agar sesuai dengan orientasi yang dipakai ML Kit.
  static img.Image rotate(img.Image src, InputImageRotation rotation) {
    return switch (rotation) {
      InputImageRotation.rotation90deg => img.copyRotate(src, angle: 90),
      InputImageRotation.rotation180deg => img.copyRotate(src, angle: 180),
      InputImageRotation.rotation270deg => img.copyRotate(src, angle: 270),
      _ => src,
    };
  }

  /// Perbesar bounding box menjadi kotak (square) dengan [scale] agar wajah tidak terlalu mepet.
  static Rect expandToSquare(
    Rect rect,
    int imageWidth,
    int imageHeight, {
    double scale = 1.2,
  }) {
    final double cx = rect.center.dx;
    final double cy = rect.center.dy;
    final double size = math.max(rect.width, rect.height) * scale;

    final double left = (cx - size / 2).clamp(0, imageWidth.toDouble());
    final double top = (cy - size / 2).clamp(0, imageHeight.toDouble());
    final double right = (cx + size / 2).clamp(0, imageWidth.toDouble());
    final double bottom = (cy + size / 2).clamp(0, imageHeight.toDouble());

    return Rect.fromLTRB(left, top, right, bottom);
  }
}

