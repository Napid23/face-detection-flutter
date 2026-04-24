import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../features/check/check_face_page.dart';
import '../features/register/register_face_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.cameras});

  final List<CameraDescription> cameras;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Face Recognition (On-Device)')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RegisterFacePage(cameras: cameras),
                      ),
                    );
                  },
                  child: const Text(
                    'Register Wajah',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 64,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CheckFacePage(cameras: cameras),
                      ),
                    );
                  },
                  child: const Text(
                    'Cek Wajah',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Catatan: Demo ini berjalan sepenuhnya on-device.\n'
                'Data wajah disimpan lokal di shared_preferences.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

