import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/face_service.dart';
import '../../services/local_face_store.dart';
import '../../utils/mlkit_camera_image_converter.dart';
import '../../widgets/face_painter.dart';

class CheckFacePage extends StatefulWidget {
  const CheckFacePage({
    super.key,
    required this.cameras,
    this.threshold = 1.0,
  });

  final List<CameraDescription> cameras;
  final double threshold;

  @override
  State<CheckFacePage> createState() => _CheckFacePageState();
}

class _CheckFacePageState extends State<CheckFacePage> {
  CameraController? _controller;
  late final FaceDetector _faceDetector;
  final _store = LocalFaceStore();

  bool _initializing = true;
  bool _detecting = false;
  bool _matching = false;
  bool _recognized = false;
  String? _error;

  InputImageRotation _latestRotation = InputImageRotation.rotation0deg;
  Size _latestImageSize = Size.zero;
  List<Face> _latestFaces = const [];

  DateTime _lastMatchAttempt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _faceDetector = GoogleMlKit.vision.faceDetector(
      FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableContours: false,
        enableLandmarks: false,
      ),
    );
    _init();
  }

  Future<void> _init() async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        setState(() {
          _error = 'Permission kamera ditolak.';
          _initializing = false;
        });
        return;
      }

      await FaceService.instance.init();

      final front = widget.cameras.where((c) {
        return c.lensDirection == CameraLensDirection.front;
      }).toList();
      final camera = front.isNotEmpty ? front.first : widget.cameras.first;

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();

      _controller = controller;
      await controller.startImageStream(_processCameraImage);

      if (!mounted) return;
      setState(() => _initializing = false);
    } catch (e) {
      setState(() {
        _error = 'Gagal inisialisasi kamera: $e';
        _initializing = false;
      });
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_recognized) return;
    if (_detecting) return;
    _detecting = true;

    try {
      final controller = _controller;
      if (controller == null) return;

      final bundle = MlKitCameraImageConverter.toInputImage(image, controller);
      if (bundle == null) return;

      final faces = await _faceDetector.processImage(bundle.inputImage);

      if (!mounted) return;
      setState(() {
        _latestRotation = bundle.rotation;
        _latestImageSize = bundle.imageSize;
        _latestFaces = faces;
      });

      await _maybeTryMatch(
        image: image,
        face: _selectBestFace(faces),
        rotation: bundle.rotation,
      );
    } catch (_) {
      // Abaikan error per-frame.
    } finally {
      _detecting = false;
    }
  }

  Future<void> _maybeTryMatch({
    required CameraImage image,
    required Face? face,
    required InputImageRotation rotation,
  }) async {
    if (_recognized) return;
    if (_matching) return;

    final now = DateTime.now();
    if (now.difference(_lastMatchAttempt) < const Duration(seconds: 1)) return;
    _lastMatchAttempt = now;

    if (face == null) return;

    _matching = true;
    try {
      final emb = await FaceService.instance.embeddingFromCameraImage(
        cameraImage: image,
        face: face,
        rotation: rotation,
      );
      if (emb == null) return;

      final stored = await _store.loadAll();
      if (stored.isEmpty) return;

      String? bestName;
      double bestDist = double.infinity;

      final current = emb.toList();
      for (final item in stored) {
        if (item.embedding.length != current.length) continue;
        final dist =
            FaceService.instance.euclideanDistance(current, item.embedding);
        if (dist < bestDist) {
          bestDist = dist;
          bestName = item.name;
        }
      }

      if (bestName != null && bestDist < widget.threshold) {
        _recognized = true;
        await _stopStream();
        if (!mounted) return;
        await _showRecognizedDialog(bestName);
      }
    } finally {
      _matching = false;
    }
  }

  Future<void> _stopStream() async {
    final c = _controller;
    if (c == null) return;
    if (c.value.isStreamingImages) {
      await c.stopImageStream();
    }
  }

  Future<void> _showRecognizedDialog(String name) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Wajah Dikenali'),
          content: Text('Wajah dikenali: $name'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    Navigator.of(context).pop(); // kembali ke Home
  }

  Face? _selectBestFace(List<Face> faces) {
    if (faces.isEmpty) return null;
    faces.sort((a, b) {
      final aa = a.boundingBox.width * a.boundingBox.height;
      final bb = b.boundingBox.width * b.boundingBox.height;
      return bb.compareTo(aa);
    });
    return faces.first;
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cek Wajah')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    final c = _controller;
    if (c == null) {
      return const Center(child: Text('Kamera belum siap.'));
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(c),
              if (_latestFaces.isNotEmpty && _latestImageSize != Size.zero)
                CustomPaint(
                  painter: FaceDetectorPainter(
                    faces: _latestFaces,
                    imageSize: _latestImageSize,
                    rotation: _latestRotation,
                    cameraLensDirection: c.description.lensDirection,
                  ),
                ),
              if (kDebugMode)
                Positioned(
                  left: 12,
                  top: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'faces=${_latestFaces.length} rot=${_latestRotation.name}\n'
                        'sensor=${c.description.sensorOrientation} lens=${c.description.lensDirection.name}',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Arahkan wajah ke kamera. Sistem akan mencoba mengenali tiap ~1 detik.',
                      style: TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
