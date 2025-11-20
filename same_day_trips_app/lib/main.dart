import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/search_screen.dart';
import 'car/car_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env file
  await dotenv.load(fileName: ".env");

  // Only initialize CarPlay/Auto and request permissions on mobile platforms
  if (!kIsWeb) {
    try {
      CarController().initialize();
    } catch (e) {
      // Safeguard: plugin may not be registered on this platform
      print('Car integration init skipped: $e');
    }

    // Request critical permissions upfront for better UX
    // WebRTC permissions (required for voice assistant)
    await Permission.camera.request();
    await Permission.microphone.request();

    // Location permission (required for trip context and map features)
    // Request both fine and coarse location for better compatibility
    await Permission.location.request();
    await Permission.locationWhenInUse.request();

    // NOTE: We do NOT request locationAlways (background location) upfront
    // as it can cause permission issues in Android Auto and is not needed
    // for the core functionality of the voice assistant

    // Calendar permissions (for trip planning and scheduling)
    await Permission.calendar.request();

    // Phone permission (for initiating calls to businesses)
    await Permission.phone.request();

    // Bluetooth permissions (for audio routing in Android Auto)
    // These are optional - the app works without them
    await Permission.bluetooth.request();
    await Permission.bluetoothConnect.request();

    // Notification permissions (Android 13+) - optional for future features
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  runApp(const SameDayTripsApp());
}

class SameDayTripsApp extends StatefulWidget {
  const SameDayTripsApp({super.key});

  @override
  State<SameDayTripsApp> createState() => _SameDayTripsAppState();
}

class _SameDayTripsAppState extends State<SameDayTripsApp> {
  bool _isAndroidAuto = false;

  @override
  void initState() {
    super.initState();
    _checkAndroidAutoMode();
  }

  Future<void> _checkAndroidAutoMode() async {
    // Skip Android Auto check on web
    if (kIsWeb) {
      setState(() {
        _isAndroidAuto = false;
      });
      return;
    }

    try {
      // Check if running in Android Auto mode
      const platform = MethodChannel('com.samedaytrips/android_auto');
      final bool isAuto = await platform.invokeMethod('isAndroidAutoMode');
      setState(() {
        _isAndroidAuto = isAuto;
      });
      print('🚗 Android Auto mode: $_isAndroidAuto');
    } catch (e) {
      print('⚠️ Error checking Android Auto mode: $e');
      setState(() {
        _isAndroidAuto = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Same-Day Trips Finder',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const SearchScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
