import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/search_screen.dart';
import 'screens/android_auto_home_screen.dart';

void main() {
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
      home: _isAndroidAuto ? const AndroidAutoHomeScreen() : const SearchScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
