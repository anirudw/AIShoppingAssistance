import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:camera/camera.dart';

import 'screens/dashboard_screen.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Camera initialization error: $e');
  }

  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('Could not load .env file: $e');
  }
  runApp(MainApp(cameras: cameras));
}

class MainApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  
  const MainApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chef RAG Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF131313),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E0FF),
          surface: Color(0xFF131313),
          surfaceContainer: Color(0xFF20201F),
          surfaceContainerHigh: Color(0xFF2A2A2A),
          surfaceContainerHighest: Color(0xFF353535),
          onSurface: Color(0xFFE5E2E1),
          onSurfaceVariant: Color(0xFF929090),
          error: Color(0xFFFFB4AB),
        ),
        textTheme: GoogleFonts.hankenGroteskTextTheme(
          ThemeData.dark().textTheme.apply(
                bodyColor: const Color(0xFFE5E2E1),
                displayColor: const Color(0xFFE5E2E1),
              ),
        ),
      ),
      home: DashboardScreen(cameras: cameras),
    );
  }
}
