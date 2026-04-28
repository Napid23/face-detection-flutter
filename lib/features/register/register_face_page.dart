import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../services/face_service.dart';
import '../../services/local_face_store.dart';
import '../check/liveness_challenge.dart';
import '../../utils/mlkit_camera_image_converter.dart';
import '../../widgets/face_painter.dart';

class RegisterFacePage extends StatefulWidget {
  const RegisterFacePage({super.key, required this.cameras});

  final List<CameraDescription> cameras;

  @override
  State<RegisterFacePage> createState() => _RegisterFacePageState();
}

class _RegisterFacePageState extends State<RegisterFacePage> {
  CameraController? _controller;
  late final FaceDetector _faceDetector;
  final _store = LocalFaceStore();
  final _liveness = LivenessChallenge();

  bool _initializing = true;
  bool _detecting = false;
  bool _captureRequested = false;
  bool _capturing = false;
  String? _error;

  // Data terbaru dari stream.
  InputImageRotation _latestRotation = InputImageRotation.rotation0deg;
  Size _latestImageSize = Size.zero;
  List<Face> _latestFaces = const [];

  @override
  void initState() {
    super.initState();
    _faceDetector = GoogleMlKit.vision.faceDetector(
      FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableClassification: true,
        enableLandmarks: true,
        enableContours: false,
        enableTracking: true,
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

      final bestFace = _selectBestFace(faces);
      if (bestFace == null) {
        _liveness.onNoFace();
      } else {
        _liveness.update(bestFace);
      }

      // Capture harus diproses di dalam callback stream agar [CameraImage] masih valid
      // (beberapa device bisa error "Bad precondition" jika dipakai di luar callback).
      if (_captureRequested && !_capturing && faces.isNotEmpty) {
        _captureRequested = false;
        _capturing = true;
        final best = bestFace ?? _selectBestFace(faces);
        if (best != null && _liveness.isPassed) {
          await _captureFromCurrentFrame(
            image: image,
            face: best,
            rotation: bundle.rotation,
          );
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_liveness.prompt)),
            );
          }
        }
        _capturing = false;
      }
    } catch (_) {
      // Abaikan error per-frame agar demo tetap jalan.
    } finally {
      _detecting = false;
    }
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

  Future<void> _onCapturePressed() async {
    final face = _selectBestFace(_latestFaces);
    if (face == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wajah belum terdeteksi.')),
      );
      return;
    }

    if (!_liveness.isPassed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_liveness.prompt)),
      );
      return;
    }

    if (_captureRequested || _capturing) return;

    // Tandai capture request: akan diproses pada frame berikutnya (di callback stream).
    _captureRequested = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Memproses frame...')),
    );
  }

  Future<void> _captureFromCurrentFrame({
    required CameraImage image,
    required Face face,
    required InputImageRotation rotation,
  }) async {
    try {
      final emb = await FaceService.instance.embeddingFromCameraImage(
        cameraImage: image,
        face: face,
        rotation: rotation,
      );
      if (emb == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal memproses gambar wajah.')),
        );
        return;
      }

      if (!mounted) return;
      await _showSaveDialog(emb);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengambil data wajah: $e')),
      );
    }
  }

  Future<void> _showSaveDialog(Float32List embedding) async {
    final nameController = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Berhasil Mengambil Data Wajah'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Nama Wajah',
              hintText: 'Contoh: Budi',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(nameController.text.trim()),
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );

    if (name == null || name.trim().isEmpty) return;

    await _store.add(
      RegisteredFace(name: name.trim(), embedding: embedding.toList()),
    );

    if (!mounted) return;
    Navigator.of(context).pop(); // kembali ke Home
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
      appBar: AppBar(title: const Text('Register Wajah')),
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
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _liveness.isPassed
                          ? 'Challenge OK. Tekan "Ambil Foto" untuk simpan wajah.'
                          : _liveness.prompt,
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
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
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: _onCapturePressed,
                child: const Text(
                  'Ambil Foto',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
