import 'package:dio/dio.dart';

/// Mapbox service for location search and routing
class MapboxService {
  static const String accessToken = 'pk.eyJ1IjoiZG9jdG9yZHVyYW50IiwiYSI6ImNtaDR4dzBzajAxdngyam9lcXI1aWc4engifQ.Byb5YxnnoFkLv8skfe_cFg';
  static const String baseUrl = 'https://api.mapbox.com';

  final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));

  /// Search for places using Search Box API (for autocomplete)
  /// Returns list of suggestions as user types
  Future<List<SearchSuggestion>> searchPlaces({
    required String query,
    double? proximityLat,
    double? proximityLng,
  }) async {
    if (query.isEmpty) return [];

    try {
      final queryParams = {
        'q': query,
        'access_token': accessToken,
        'session_token': DateTime.now().millisecondsSinceEpoch.toString(),
        'limit': 5,
      };

      // Add proximity if location provided (biases results near destination)
      if (proximityLat != null && proximityLng != null) {
        queryParams['proximity'] = '$proximityLng,$proximityLat';
      }

      final response = await _dio.get(
        '/search/searchbox/v1/suggest',
        queryParameters: queryParams,
      );

      final suggestions = response.data['suggestions'] as List? ?? [];
      return suggestions.map((item) => SearchSuggestion.fromJson(item)).toList();
    } catch (e) {
      print('⚠️ Mapbox search failed: $e');
      return [];
    }
  }

  /// Retrieve full details for a selected suggestion
  Future<PlaceDetails?> retrievePlaceDetails({
    required String mapboxId,
    required String sessionToken,
  }) async {
    try {
      final response = await _dio.get(
        '/search/searchbox/v1/retrieve/$mapboxId',
        queryParameters: {
          'access_token': accessToken,
          'session_token': sessionToken,
        },
      );

      final features = response.data['features'] as List? ?? [];
      if (features.isEmpty) return null;

      return PlaceDetails.fromJson(features[0]);
    } catch (e) {
      print('⚠️ Mapbox retrieve failed: $e');
      return null;
    }
  }

  /// Calculate travel times between multiple points using Matrix API
  /// Returns a matrix of durations in seconds
  Future<List<List<double>>> calculateTravelTimes({
    required List<MapLocation> locations,
    String profile = 'driving-traffic',
  }) async {
    if (locations.length < 2) {
      throw Exception('Need at least 2 locations for Matrix API');
    }

    try {
      // Build coordinates string: "lng,lat;lng,lat;..."
      final coordinates = locations
          .map((loc) => '${loc.longitude},${loc.latitude}')
          .join(';');

      final response = await _dio.get(
        '/directions-matrix/v1/mapbox/$profile/$coordinates',
        queryParameters: {
          'access_token': accessToken,
          'sources': List.generate(locations.length, (i) => i).join(';'),
          'destinations': List.generate(locations.length, (i) => i).join(';'),
        },
      );

      // Parse duration matrix
      final durations = response.data['durations'] as List? ?? [];
      return durations
          .map((row) => (row as List).map((d) => (d as num).toDouble()).toList())
          .toList();
    } catch (e) {
      print('⚠️ Mapbox Matrix API failed: $e');
      rethrow;
    }
  }

  /// Calculate route timeline for airport → stops → airport
  Future<RouteTimeline?> calculateRouteTimeline({
    required MapLocation airport,
    required List<StopWithLocation> stops,
  }) async {
    if (stops.isEmpty) return null;

    try {
      // Build location list: airport, stop1, stop2, ..., airport
      final locations = <MapLocation>[
        airport,
        ...stops.map((s) => s.location),
        airport,
      ];

      // Get travel time matrix
      final matrix = await calculateTravelTimes(locations: locations);

      // Calculate leg durations: airport→stop1, stop1→stop2, ..., lastStop→airport
      final legDurations = <double>[];
      for (var i = 0; i < locations.length - 1; i++) {
        legDurations.add(matrix[i][i + 1]);
      }

      return RouteTimeline(
        legDurations: legDurations,
        stops: stops,
        airport: airport,
      );
    } catch (e) {
      print('⚠️ Route timeline calculation failed: $e');
      return null;
    }
  }
}

/// Search suggestion from Search Box API
class SearchSuggestion {
  final String mapboxId;
  final String name;
  final String fullAddress;
  final String? placeFormatted;

  SearchSuggestion({
    required this.mapboxId,
    required this.name,
    required this.fullAddress,
    this.placeFormatted,
  });

  factory SearchSuggestion.fromJson(Map<String, dynamic> json) {
    return SearchSuggestion(
      mapboxId: json['mapbox_id'] as String,
      name: json['name'] as String,
      fullAddress: json['full_address'] as String? ?? '',
      placeFormatted: json['place_formatted'] as String?,
    );
  }

  String get displayText => placeFormatted ?? fullAddress;
}

/// Full place details from retrieve endpoint
class PlaceDetails {
  final String name;
  final String fullAddress;
  final double latitude;
  final double longitude;

  PlaceDetails({
    required this.name,
    required this.fullAddress,
    required this.latitude,
    required this.longitude,
  });

  factory PlaceDetails.fromJson(Map<String, dynamic> json) {
    final geometry = json['geometry'] as Map<String, dynamic>;
    final coordinates = geometry['coordinates'] as List;
    final properties = json['properties'] as Map<String, dynamic>;

    return PlaceDetails(
      name: properties['name'] as String? ?? '',
      fullAddress: properties['full_address'] as String? ?? '',
      longitude: (coordinates[0] as num).toDouble(),
      latitude: (coordinates[1] as num).toDouble(),
    );
  }
}

/// Simple location with lat/lng
class MapLocation {
  final double latitude;
  final double longitude;

  MapLocation({required this.latitude, required this.longitude});
}

/// Stop with location
class StopWithLocation {
  final String name;
  final int durationMinutes;
  final MapLocation location;

  StopWithLocation({
    required this.name,
    required this.durationMinutes,
    required this.location,
  });
}

/// Route timeline with drive times
class RouteTimeline {
  final List<double> legDurations; // In seconds
  final List<StopWithLocation> stops;
  final MapLocation airport;

  RouteTimeline({
    required this.legDurations,
    required this.stops,
    required this.airport,
  });

  /// Total driving time in minutes
  double get totalDrivingMinutes {
    return legDurations.fold(0.0, (sum, duration) => sum + duration) / 60.0;
  }

  /// Total stop time in minutes
  int get totalStopMinutes {
    return stops.fold(0, (sum, stop) => sum + stop.durationMinutes);
  }

  /// Total time needed (driving + stops) in minutes
  double get totalMinutes {
    return totalDrivingMinutes + totalStopMinutes;
  }

  /// Format duration in seconds to "Xh YYm" or "XX min"
  String formatDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) {
      return '$minutes min';
    }
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) {
      return '${hours}h';
    }
    return '${hours}h ${mins}m';
  }
}
