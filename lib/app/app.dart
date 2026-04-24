import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'home_page.dart';

class AppRoot extends StatelessWidget {
  const AppRoot({super.key, required this.cameras});

  final List<CameraDescription> cameras;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Recognition Absensi Simplifikasi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: HomePage(cameras: cameras),
    );
  }
}

