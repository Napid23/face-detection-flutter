import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../utils/image_utils.dart';

class FaceService {
  FaceService._();

  static final FaceService instance = FaceService._();

  Interpreter? _interpreter;
  int _inputSize = 112;
  int _embeddingLength = 128;
  TensorType? _inputTensorType;
  int? _expectedInputBytes;

  int get embeddingLength => _embeddingLength;
  int get inputSize => _inputSize;

  Future<void> init() async {
    if (_interpreter != null) return;

    final options = InterpreterOptions()..threads = 2;
    _interpreter = await Interpreter.fromAsset(
      'assets/mobilefacenet.tflite',
      options: options,
    );

    final inputTensor = _interpreter!.getInputTensor(0);
    final inputShape = inputTensor.shape; // [1, H, W, 3]
    if (inputShape.length >= 4) {
      _inputSize = inputShape[1];
    }
    _inputTensorType = inputTensor.type;
    _expectedInputBytes = inputTensor.numBytes();

    final outputShape = _interpreter!.getOutputTensor(0).shape; // [1, N]
    if (outputShape.length >= 2) {
      _embeddingLength = outputShape[1];
    }

    if (kDebugMode) {
      debugPrint(
        '[FaceService] input shape=$inputShape type=${_inputTensorType?.name} bytes=$_expectedInputBytes '
        'output shape=$outputShape',
      );
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }

  /// Menghasilkan embedding (vektor) dari wajah yang sudah dipotong & diresize.
  Float32List embed(img.Image faceImage) {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('FaceService belum di-init. Panggil init() dulu.');
    }

    final img.Image resized = img.copyResize(
      faceImage,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    // Penting: jangan kirim `Float32List` langsung ke `interpreter.run`, karena
    // `tflite_flutter` akan menganggapnya sebagai `List` 1D dan mencoba
    // `resizeInputTensor` menjadi [N], yang bisa bikin TFLite error
    // "Bad state: Failed precondition".
    final inputBytes = _imageToInputBytes(resized);
    final expected = _expectedInputBytes;
    if (expected != null && inputBytes.length != expected) {
      throw StateError(
        'Input bytes mismatch. got=${inputBytes.length} expected=$expected '
        'type=${_inputTensorType?.name} size=$_inputSize',
      );
    }
    final output = List.generate(1, (_) => List.filled(_embeddingLength, 0.0));
    interpreter.run(inputBytes, output);

    final emb = output.first.map((e) => (e as num).toDouble()).toList();
    return Float32List.fromList(emb);
  }

  /// Pipeline lengkap: dari [CameraImage] + [Face] (ML Kit) -> crop -> embedding.
  Future<Float32List?> embeddingFromCameraImage({
    required CameraImage cameraImage,
    required Face face,
    required InputImageRotation rotation,
  }) async {
    final rgb = ImageUtils.cameraImageToImage(cameraImage);
    if (rgb == null) return null;

    // Samakan orientasi image dengan koordinat bounding box ML Kit.
    final oriented = ImageUtils.rotate(rgb, rotation);

    // Kotak wajah dari ML Kit.
    final square = ImageUtils.expandToSquare(
      face.boundingBox,
      oriented.width,
      oriented.height,
      scale: 1.25,
    );

    final int x = square.left.floor().clamp(0, oriented.width - 1);
    final int y = square.top.floor().clamp(0, oriented.height - 1);
    final int w = square.width.floor().clamp(1, oriented.width - x);
    final int h = square.height.floor().clamp(1, oriented.height - y);

    final cropped = img.copyCrop(oriented, x: x, y: y, width: w, height: h);
    return embed(cropped);
  }

  /// Euclidean distance untuk membandingkan embedding.
  double euclideanDistance(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw ArgumentError('Panjang vektor berbeda: ${a.length} vs ${b.length}');
    }
    double sum = 0;
    for (int i = 0; i < a.length; i++) {
      final d = a[i] - b[i];
      sum += d * d;
    }
    return math.sqrt(sum);
  }

  Float32List _imageToFloat32(img.Image image) {
    // MobileFaceNet biasanya memakai normalisasi ke rentang [-1, 1]
    // (x - 127.5) / 128.0.
    final Float32List converted =
        Float32List(1 * _inputSize * _inputSize * 3);
    int idx = 0;
    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();
        converted[idx++] = (r - 127.5) / 128.0;
        converted[idx++] = (g - 127.5) / 128.0;
        converted[idx++] = (b - 127.5) / 128.0;
      }
    }
    return converted;
  }

  Uint8List _imageToInputBytes(img.Image image) {
    final type = _inputTensorType ?? TensorType.float32;
    switch (type) {
      case TensorType.float32:
        final f32 = _imageToFloat32(image);
        return Uint8List.view(f32.buffer);
      case TensorType.uint8:
        // Quantized model: kirim 0..255 apa adanya (tanpa normalisasi).
        // Catatan: untuk kualitas terbaik, idealnya pakai scale/zeroPoint tensor.
        final out = Uint8List(_inputSize * _inputSize * 3);
        int idx = 0;
        for (int y = 0; y < _inputSize; y++) {
          for (int x = 0; x < _inputSize; x++) {
            final pixel = image.getPixel(x, y);
            out[idx++] = pixel.r.toInt();
            out[idx++] = pixel.g.toInt();
            out[idx++] = pixel.b.toInt();
          }
        }
        return out;
      case TensorType.float16:
        // Float16 model: konversi float32 -> float16 (little endian).
        final f32 = _imageToFloat32(image);
        final out = Uint8List(f32.length * 2);
        final bd = ByteData.view(out.buffer);
        for (int i = 0; i < f32.length; i++) {
          bd.setUint16(i * 2, _float32ToFloat16Bits(f32[i]), Endian.little);
        }
        return out;
      default:
        throw UnsupportedError('Unsupported input tensor type: ${type.name}');
    }
  }

  // Konversi float32 ke float16 bits (IEEE 754 binary16).
  int _float32ToFloat16Bits(double value) {
    final f32 = Float32List(1)..[0] = value.toDouble();
    final u32 = ByteData.view(f32.buffer).getUint32(0, Endian.little);

    final sign = (u32 >> 31) & 0x1;
    var exp = (u32 >> 23) & 0xFF;
    var mant = u32 & 0x7FFFFF;

    // NaN / Inf
    if (exp == 0xFF) {
      if (mant != 0) {
        return (sign << 15) | 0x7E00; // qNaN
      }
      return (sign << 15) | 0x7C00; // inf
    }

    // Normalized/denormalized conversion
    // float32 bias=127, float16 bias=15
    int halfExp = exp - 127 + 15;

    if (halfExp >= 0x1F) {
      // overflow -> inf
      return (sign << 15) | 0x7C00;
    }

    if (halfExp <= 0) {
      // subnormal or underflow
      if (halfExp < -10) {
        return (sign << 15); // too small -> 0
      }
      // make implicit leading 1 explicit
      mant |= 0x800000;
      final shift = 14 - halfExp;
      int halfMant = (mant >> shift);
      // round
      if ((mant >> (shift - 1)) & 0x1 == 1) {
        halfMant += 1;
      }
      return (sign << 15) | (halfMant & 0x3FF);
    }

    // normal half
    int halfMant = mant >> 13;
    // round to nearest
    if ((mant & 0x1000) != 0) {
      halfMant += 1;
      if (halfMant == 0x400) {
        halfMant = 0;
        halfExp += 1;
        if (halfExp >= 0x1F) {
          return (sign << 15) | 0x7C00;
        }
      }
    }

    return (sign << 15) | ((halfExp & 0x1F) << 10) | (halfMant & 0x3FF);
  }
}
