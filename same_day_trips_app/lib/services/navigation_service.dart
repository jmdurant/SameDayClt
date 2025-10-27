import 'package:flutter/services.dart';

class NavigationService {
  static const platform = MethodChannel('com.samedaytrips/android_auto');

  /// Launch Google Maps navigation to a destination
  /// Works on both phone and Android Auto
  static Future<bool> launchNavigation(String destination) async {
    try {
      final bool result = await platform.invokeMethod('launchNavigation', {
        'destination': destination,
      });
      return result;
    } catch (e) {
      print('⚠️ Error launching navigation: $e');
      return false;
    }
  }

  /// Launch Google Maps with multiple waypoints
  /// destination: final destination address or coordinates
  /// waypoints: list of stop addresses/coordinates
  static Future<bool> launchNavigationWithWaypoints({
    required String destination,
    required List<String> waypoints,
  }) async {
    try {
      final bool result = await platform.invokeMethod('launchNavigationWithWaypoints', {
        'destination': destination,
        'waypoints': waypoints,
      });
      return result;
    } catch (e) {
      print('⚠️ Error launching navigation with waypoints: $e');
      return false;
    }
  }

  /// Check if running in Android Auto mode
  static Future<bool> isAndroidAutoMode() async {
    try {
      final bool result = await platform.invokeMethod('isAndroidAutoMode');
      return result;
    } catch (e) {
      print('⚠️ Error checking Android Auto mode: $e');
      return false;
    }
  }
}

