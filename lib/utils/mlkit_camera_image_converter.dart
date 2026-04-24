import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

typedef MlKitImageBundle = ({
  InputImage inputImage,
  Size imageSize,
  InputImageRotation rotation,
});

class MlKitCameraImageConverter {
  /// Konversi [CameraImage] menjadi [InputImage] yang lebih kompatibel lintas device.
  ///
  /// Kenapa ini penting:
  /// - Beberapa device Android kurang stabil jika kita mengirim byte mentah YUV420_888
  ///   dengan cara "concat planes". Konversi ke NV21 biasanya paling kompatibel.
  static MlKitImageBundle? toInputImage(
    CameraImage image,
    CameraController controller,
  ) {
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final rotation = _rotationFromController(controller);

    // Android: stabilkan dengan NV21.
    final looksLikeYuv420 = image.planes.length == 3;
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        (image.format.group == ImageFormatGroup.yuv420 || looksLikeYuv420)) {
      final bytes = _yuv420ToNv21(image);
      final metadata = InputImageMetadata(
        size: imageSize,
        rotation: rotation,
        format: InputImageFormat.nv21,
        // NV21 rowStride umumnya = width.
        bytesPerRow: image.width,
      );

      return (
        inputImage: InputImage.fromBytes(bytes: bytes, metadata: metadata),
        imageSize: imageSize,
        rotation: rotation,
      );
    }

    // BGRA (umumnya iOS).
    if (image.format.group == ImageFormatGroup.bgra8888) {
      final plane = image.planes.first;
      final metadata = InputImageMetadata(
        size: imageSize,
        rotation: rotation,
        format: InputImageFormat.bgra8888,
        bytesPerRow: plane.bytesPerRow,
      );
      return (
        inputImage: InputImage.fromBytes(bytes: plane.bytes, metadata: metadata),
        imageSize: imageSize,
        rotation: rotation,
      );
    }

    // Fallback: concat plane bytes + format dari raw value.
    final bytes = _concatenatePlanes(image.planes);
    final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
        (defaultTargetPlatform == TargetPlatform.android
            ? InputImageFormat.yuv_420_888
            : InputImageFormat.yuv420);
    final metadata = InputImageMetadata(
      size: imageSize,
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );
    return (
      inputImage: InputImage.fromBytes(bytes: bytes, metadata: metadata),
      imageSize: imageSize,
      rotation: rotation,
    );
  }

  static Uint8List _concatenatePlanes(List<Plane> planes) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  /// Mapping rotasi berdasarkan sensor + orientasi device (mirip contoh ML Kit).
  static InputImageRotation _rotationFromController(CameraController controller) {
    final sensorOrientation = controller.description.sensorOrientation;

    final deviceOrientation = controller.value.deviceOrientation;
    final rotationDegrees = switch (deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };

    int rotationCompensation;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      rotationCompensation = (sensorOrientation - rotationDegrees + 360) % 360;
    } else {
      rotationCompensation = (sensorOrientation + rotationDegrees) % 360;
    }

    return InputImageRotationValue.fromRawValue(rotationCompensation) ??
        InputImageRotation.rotation0deg;
  }

  /// YUV420_888 -> NV21 (VU interleaved) untuk Android.
  static Uint8List _yuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yRowStride = yPlane.bytesPerRow;
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;

    final out = Uint8List(width * height + (width * height ~/ 2));

    // Copy Y dengan memperhatikan rowStride.
    int outIndex = 0;
    for (int row = 0; row < height; row++) {
      final yRowStart = row * yRowStride;
      for (int col = 0; col < width; col++) {
        out[outIndex++] = yPlane.bytes[yRowStart + col];
      }
    }

    // Interleave VU.
    final uvHeight = height ~/ 2;
    final uvWidth = width ~/ 2;
    for (int row = 0; row < uvHeight; row++) {
      final uvRowStart = row * uvRowStride;
      for (int col = 0; col < uvWidth; col++) {
        final uvOffset = uvRowStart + col * uvPixelStride;
        out[outIndex++] = vPlane.bytes[uvOffset];
        out[outIndex++] = uPlane.bytes[uvOffset];
      }
    }

    return out;
  }
}
