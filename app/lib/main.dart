import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Erro ao listar câmeras: $e');
  }
  runApp(const PhotoDetectorApp());
}

class PhotoDetectorApp extends StatelessWidget {
  const PhotoDetectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Detector de Objetos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: HomeScreen(cameras: cameras),
    );
  }
}
