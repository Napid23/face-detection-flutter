import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Demo simplifikasi: kunci orientasi portrait untuk memudahkan mapping rotasi
  // dan koordinat bounding box dari ML Kit.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final cameras = await availableCameras();
  runApp(AppRoot(cameras: cameras));
}

