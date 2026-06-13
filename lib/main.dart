import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/dashboard_screen.dart';
import 'services/cart_service.dart';

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

  // Initialize Supabase using values from .env
  try {
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL'] ?? '',
      publishableKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
    );
  } catch (e) {
    debugPrint('Supabase initialization error: $e');
  }

  // Pre-load cart session from persistent storage before rendering.
  await CartService().load();

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
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFF4F7F8),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF23C8D9),
          secondary: Color(0xFF0EAFC4),
          surface: Color(0xFFFFFFFF),
          surfaceContainer: Color(0xFFF9FAFB),
          surfaceContainerHigh: Color(0xFFFAFAFA),
          onSurface: Color(0xFF111827),
          onSurfaceVariant: Color(0xFF6B7280),
          error: Color(0xFFEF4444),
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.light().textTheme.apply(
                bodyColor: const Color(0xFF111827),
                displayColor: const Color(0xFF111827),
              ),
        ),
      ),
      home: DashboardScreen(cameras: cameras),
    );
  }
}
