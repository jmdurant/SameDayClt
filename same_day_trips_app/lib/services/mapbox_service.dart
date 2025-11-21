import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Mapbox service for location search and routing
class MapboxService {
  static String get accessToken => dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
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

  /// Calculate travel times and distances between multiple points using Matrix API
  /// Returns a tuple: (durations matrix in seconds, distances matrix in meters)
  Future<(List<List<double>>, List<List<double>>)> calculateTravelTimesAndDistances({
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
          'annotations': 'duration,distance', // Request both duration and distance
        },
      );

      // Parse duration matrix
      final durations = response.data['durations'] as List? ?? [];
      final durationMatrix = durations
          .map((row) => (row as List)
              .map((d) => d == null ? double.infinity : (d as num).toDouble())
              .toList())
          .toList();

      // Parse distance matrix (in meters)
      final distances = response.data['distances'] as List? ?? [];
      final distanceMatrix = distances
          .map((row) => (row as List)
              .map((d) => d == null ? double.infinity : (d as num).toDouble())
              .toList())
          .toList();

      return (durationMatrix, distanceMatrix);
    } catch (e) {
      print('⚠️ Mapbox Matrix API failed: $e');
      rethrow;
    }
  }

  /// Calculate travel times between multiple points using Matrix API
  /// Returns a matrix of durations in seconds
  Future<List<List<double>>> calculateTravelTimes({
    required List<MapLocation> locations,
    String profile = 'driving-traffic',
  }) async {
    final (durations, _) = await calculateTravelTimesAndDistances(
      locations: locations,
      profile: profile,
    );
    return durations;
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

      // Get travel time and distance matrices
      final (durationMatrix, distanceMatrix) = await calculateTravelTimesAndDistances(locations: locations);

      // Calculate leg durations and distances: airport→stop1, stop1→stop2, ..., lastStop→airport
      final legDurations = <double>[];
      final legDistances = <double>[];
      for (var i = 0; i < locations.length - 1; i++) {
        legDurations.add(durationMatrix[i][i + 1]);
        legDistances.add(distanceMatrix[i][i + 1]);
      }

      return RouteTimeline(
        legDurations: legDurations,
        legDistances: legDistances,
        stops: stops,
        airport: airport,
      );
    } catch (e) {
      print('⚠️ Route timeline calculation failed: $e');
      return null;
    }
  }

  /// Plan the most efficient loop (airport -> stops -> airport) using the Matrix API
  Future<RouteTimeline?> planOptimalRoute({
    required MapLocation airport,
    required List<StopWithLocation> stops,
    String profile = 'driving-traffic',
  }) async {
    if (stops.isEmpty) return null;
    if (stops.length == 1) {
      return calculateRouteTimeline(airport: airport, stops: stops);
    }

    try {
      // Build locations list for matrix: airport, stops..., airport
      final locations = <MapLocation>[airport, ...stops.map((s) => s.location), airport];
      final (matrixSeconds, matrixMeters) = await calculateTravelTimesAndDistances(locations: locations, profile: profile);
      final matrixMinutes = matrixSeconds
          .map((row) => row.map((d) => d / 60.0).toList())
          .toList();

      final stopCount = stops.length;
      final stopIndexes = List.generate(stopCount, (i) => i + 1); // Matrix indexes for stops

      double bestCost = double.infinity;
      List<int> bestOrder = stopIndexes;

      // Brute force permutations (stop counts are small in UI)
      void permute(List<int> current, List<int> remaining) {
        if (remaining.isEmpty) {
          final cost = _evaluateOrder(current, matrixMinutes, stops);
          if (cost != null && cost < bestCost) {
            bestCost = cost;
            bestOrder = List<int>.from(current);
          }
          return;
        }

        for (var i = 0; i < remaining.length; i++) {
          final next = remaining[i];
          final nextCurrent = List<int>.from(current)..add(next);
          final nextRemaining = List<int>.from(remaining)..removeAt(i);
          permute(nextCurrent, nextRemaining);
        }
      }

      for (var i = 0; i < stopIndexes.length; i++) {
        final start = stopIndexes[i];
        final remaining = List<int>.from(stopIndexes)..removeAt(i);
        permute([start], remaining);
      }

      if (bestCost == double.infinity) {
        return null;
      }

      final orderedStops = bestOrder.map((idx) => stops[idx - 1]).toList();
      final legDurations = _buildLegDurations(bestOrder, matrixMinutes);
      final legDistances = _buildLegDistances(bestOrder, matrixMeters);

      return RouteTimeline(
        legDurations: legDurations,
        legDistances: legDistances,
        stops: orderedStops,
        airport: airport,
      );
    } catch (e) {
      print('⚠️ Optimal routing failed: $e');
      return null;
    }
  }

  double? _evaluateOrder(
    List<int> order,
    List<List<double>> matrixMinutes,
    List<StopWithLocation> stops,
  ) {
    final stopCount = stops.length;

    double firstLeg = matrixMinutes[0][order.first];
    if (firstLeg.isInfinite) return null;

    double cumulative = firstLeg;
    double? bestBase;

    for (var o = 0; o < order.length; o++) {
      final stop = stops[order[o] - 1];

      if (stop.startTime != null) {
        final startMinutes = stop.startTime!.hour * 60 + stop.startTime!.minute;
        final candidateBase = startMinutes - cumulative;
        bestBase = bestBase == null ? candidateBase : (candidateBase < bestBase ? candidateBase : bestBase);
      }

      cumulative += stop.durationMinutes.toDouble();

      if (o < order.length - 1) {
        final leg = matrixMinutes[order[o]][order[o + 1]];
        if (leg.isInfinite) return null;
        cumulative += leg;
      }
    }
    final finalLeg = matrixMinutes[order.last][stopCount + 1];
    if (finalLeg.isInfinite) return null;
    cumulative += finalLeg;

    final base = bestBase ?? 0;

    // Validate schedule: ensure each fixed event is on time (arrival <= start)
    double running = base + matrixMinutes[0][order.first];
    for (var o = 0; o < order.length; o++) {
      final stop = stops[order[o] - 1];

      if (stop.startTime != null) {
        final startMinutes = stop.startTime!.hour * 60 + stop.startTime!.minute;
        if (running > startMinutes) {
          return null; // late to a fixed event
        }
      }

      running += stop.durationMinutes.toDouble();
      if (o < order.length - 1) {
        running += matrixMinutes[order[o]][order[o + 1]];
      }
    }

    // Cost: total driving minutes (not counting waits)
    double drive = 0;
    drive += firstLeg;
    for (var i = 0; i < order.length - 1; i++) {
      final leg = matrixMinutes[order[i]][order[i + 1]];
      if (leg.isInfinite) return null;
      drive += leg;
    }
    drive += finalLeg;
    return drive;
  }

  List<double> _buildLegDurations(List<int> order, List<List<double>> matrixMinutes) {
    final stopCount = order.length;
    final legDurations = <double>[];

    legDurations.add(matrixMinutes[0][order.first] * 60);
    for (var i = 0; i < stopCount - 1; i++) {
      legDurations.add(matrixMinutes[order[i]][order[i + 1]] * 60);
    }
    legDurations.add(matrixMinutes[order.last][stopCount + 1] * 60);

    return legDurations;
  }

  List<double> _buildLegDistances(List<int> order, List<List<double>> matrixMeters) {
    final stopCount = order.length;
    final legDistances = <double>[];

    legDistances.add(matrixMeters[0][order.first]);
    for (var i = 0; i < stopCount - 1; i++) {
      legDistances.add(matrixMeters[order[i]][order[i + 1]]);
    }
    legDistances.add(matrixMeters[order.last][stopCount + 1]);

    return legDistances;
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
  final DateTime? startTime; // Optional scheduled start

  StopWithLocation({
    required this.name,
    required this.durationMinutes,
    required this.location,
    this.startTime,
  });
}

/// Route timeline with drive times and distances
class RouteTimeline {
  final List<double> legDurations; // In seconds
  final List<double> legDistances; // In meters
  final List<StopWithLocation> stops;
  final MapLocation airport;

  RouteTimeline({
    required this.legDurations,
    required this.legDistances,
    required this.stops,
    required this.airport,
  });

  /// Total driving time in minutes
  double get totalDrivingMinutes {
    return legDurations.fold(0.0, (sum, duration) => sum + duration) / 60.0;
  }

  /// Total driving distance in miles
  double get totalDrivingMiles {
    return legDistances.fold(0.0, (sum, distance) => sum + distance) * 0.000621371; // Convert meters to miles
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
    if (seconds.isInfinite || seconds.isNaN) return 'N/A';
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

  /// Generate detailed agenda with actual times
  /// Returns null if the schedule is invalid or times can't be parsed
  AgendaTimeline? generateAgenda({
    required String arrivalTimeIso, // ISO timestamp from flight arrival
    required String departureTimeIso, // ISO timestamp from flight departure
    int airportExitMinutes = 20, // Time to exit airport after arrival
    int airportBufferMinutes = 45, // Time to arrive at airport before departure
  }) {
    try {
      final arrivalTime = DateTime.parse(arrivalTimeIso);
      final departureTime = DateTime.parse(departureTimeIso);

      // Calculate available time window
      final startTime = arrivalTime.add(Duration(minutes: airportExitMinutes));
      final endTime = departureTime.subtract(Duration(minutes: airportBufferMinutes));

      if (startTime.isAfter(endTime)) {
        return null; // Invalid time window
      }

      final availableMinutes = endTime.difference(startTime).inMinutes;

      // Build agenda items
      final items = <AgendaItem>[];
      var currentTime = startTime;

      // First leg: Airport → First Stop
      final firstDriveMinutes = (legDurations[0] / 60).round();
      final firstDistanceMiles = legDistances[0] * 0.000621371; // Convert meters to miles
      items.add(AgendaItem(
        time: currentTime,
        type: AgendaItemType.travel,
        description: 'Depart airport → ${stops[0].name}',
        durationMinutes: firstDriveMinutes,
        distanceMiles: firstDistanceMiles,
      ));
      currentTime = currentTime.add(Duration(minutes: firstDriveMinutes));

      // Stops and travel between them
      for (var i = 0; i < stops.length; i++) {
        final stop = stops[i];

        // Add stop
        items.add(AgendaItem(
          time: currentTime,
          type: AgendaItemType.stop,
          description: stop.name,
          durationMinutes: stop.durationMinutes,
        ));
        currentTime = currentTime.add(Duration(minutes: stop.durationMinutes));

        // Add travel to next stop or back to airport
        final nextDriveMinutes = (legDurations[i + 1] / 60).round();
        final nextDistanceMiles = legDistances[i + 1] * 0.000621371;
        final nextDescription = i < stops.length - 1
            ? '${stop.name} → ${stops[i + 1].name}'
            : '${stop.name} → Return to airport';

        items.add(AgendaItem(
          time: currentTime,
          type: AgendaItemType.travel,
          description: nextDescription,
          durationMinutes: nextDriveMinutes,
          distanceMiles: nextDistanceMiles,
        ));
        currentTime = currentTime.add(Duration(minutes: nextDriveMinutes));
      }

      // Calculate remaining time
      final totalUsedMinutes = endTime.difference(startTime).inMinutes -
          endTime.difference(currentTime).inMinutes;
      final remainingMinutes = endTime.difference(currentTime).inMinutes;

      final isFeasible = remainingMinutes >= 0;

      return AgendaTimeline(
        items: items,
        arrivalTime: arrivalTime,
        departureTime: departureTime,
        startTime: startTime,
        endTime: endTime,
        remainingMinutes: remainingMinutes,
        isFeasible: isFeasible,
        airportExitMinutes: airportExitMinutes,
        airportBufferMinutes: airportBufferMinutes,
      );
    } catch (e) {
      print('⚠️ Failed to generate agenda: $e');
      return null;
    }
  }
}

/// Timeline agenda with actual times
class AgendaTimeline {
  final List<AgendaItem> items;
  final DateTime arrivalTime; // Flight arrival
  final DateTime departureTime; // Flight departure
  final DateTime startTime; // When you can start (arrival + exit time)
  final DateTime endTime; // When you must be at airport (departure - buffer)
  final int remainingMinutes; // Minutes left after all stops (negative if overbooked)
  final bool isFeasible; // Whether the schedule fits
  final int airportExitMinutes;
  final int airportBufferMinutes;

  AgendaTimeline({
    required this.items,
    required this.arrivalTime,
    required this.departureTime,
    required this.startTime,
    required this.endTime,
    required this.remainingMinutes,
    required this.isFeasible,
    required this.airportExitMinutes,
    required this.airportBufferMinutes,
  });

  /// Get formatted remaining time message
  String get remainingTimeMessage {
    if (!isFeasible) {
      final overMinutes = remainingMinutes.abs();
      final hours = overMinutes ~/ 60;
      final mins = overMinutes % 60;
      if (hours == 0) {
        return 'Not enough time - remove $mins minutes of activities';
      }
      return mins == 0
          ? 'Not enough time - remove ${hours}h of activities'
          : 'Not enough time - remove ${hours}h ${mins}m of activities';
    }

    final hours = remainingMinutes ~/ 60;
    final mins = remainingMinutes % 60;
    if (hours == 0) {
      return 'You still have $mins minutes to schedule another stop';
    }
    return mins == 0
        ? 'You still have ${hours}h to schedule another stop'
        : 'You still have ${hours}h ${mins}m to schedule another stop';
  }
}

/// Individual agenda item
class AgendaItem {
  final DateTime time;
  final AgendaItemType type;
  final String description;
  final int durationMinutes;
  final double? distanceMiles; // Distance for travel items (in miles)

  AgendaItem({
    required this.time,
    required this.type,
    required this.description,
    required this.durationMinutes,
    this.distanceMiles,
  });

  /// Get end time
  DateTime get endTime => time.add(Duration(minutes: durationMinutes));
}

enum AgendaItemType {
  travel,
  stop,
}
