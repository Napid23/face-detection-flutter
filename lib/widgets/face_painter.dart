import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

class FaceDetectorPainter extends CustomPainter {
  FaceDetectorPainter({
    required this.faces,
    required this.imageSize,
    required this.rotation,
    required this.cameraLensDirection,
  });

  final List<Face> faces;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.lightGreenAccent;

    for (final face in faces) {
      final rect = _transformRect(face.boundingBox, size);
      canvas.drawRect(rect, paint);
    }
  }

  Rect _transformRect(Rect rect, Size widgetSize) {
    final left = _translateX(rect.left, widgetSize);
    final top = _translateY(rect.top, widgetSize);
    final right = _translateX(rect.right, widgetSize);
    final bottom = _translateY(rect.bottom, widgetSize);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  double _scaleX(double x, Size widgetSize) {
    return switch (rotation) {
      InputImageRotation.rotation90deg ||
      InputImageRotation.rotation270deg =>
        x * widgetSize.width / imageSize.height,
      _ => x * widgetSize.width / imageSize.width,
    };
  }

  double _scaleY(double y, Size widgetSize) {
    return switch (rotation) {
      InputImageRotation.rotation90deg ||
      InputImageRotation.rotation270deg =>
        y * widgetSize.height / imageSize.width,
      _ => y * widgetSize.height / imageSize.height,
    };
  }

  double _translateX(double x, Size widgetSize) {
    switch (rotation) {
      case InputImageRotation.rotation270deg:
        return widgetSize.width - _scaleX(x, widgetSize);
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        if (cameraLensDirection == CameraLensDirection.front) {
          return widgetSize.width - _scaleX(x, widgetSize);
        }
        return _scaleX(x, widgetSize);
      case InputImageRotation.rotation90deg:
        return _scaleX(x, widgetSize);
    }
  }

  double _translateY(double y, Size widgetSize) {
    switch (rotation) {
      case InputImageRotation.rotation180deg:
        return widgetSize.height - _scaleY(y, widgetSize);
      default:
        return _scaleY(y, widgetSize);
    }
  }

  @override
  bool shouldRepaint(covariant FaceDetectorPainter oldDelegate) {
    return oldDelegate.faces != faces ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.rotation != rotation ||
        oldDelegate.cameraLensDirection != cameraLensDirection;
  }
}

