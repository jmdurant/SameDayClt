import 'package:dio/dio.dart';
import '../models/flight_offer.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Direct Amadeus API service - no Flask server required!
class AmadeusService {
  static const String baseUrl = 'https://api.amadeus.com';
  static String get apiKey => dotenv.env['AMADEUS_CLIENT_ID'] ?? '';
  static String get apiSecret => dotenv.env['AMADEUS_CLIENT_SECRET'] ?? '';

  final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));

  String? _token;
  DateTime? _tokenExpiry;

  /// Authenticate with Amadeus API and get access token
  Future<void> authenticate() async {
    // Skip if token is still valid
    if (_token != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return;
    }

    try {
      final response = await _dio.post(
        '/v1/security/oauth2/token',
        data: {
          'grant_type': 'client_credentials',
          'client_id': apiKey,
          'client_secret': apiSecret,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      _token = response.data['access_token'];
      final expiresIn = response.data['expires_in'] as int;
      _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));

      print('✅ Amadeus API authenticated');
    } catch (e) {
      print('❌ Amadeus authentication failed: $e');
      rethrow;
    }
  }

  /// Find nearest airport to a geographic location
  /// Uses Airport Nearest Relevant API - replaces manual airport lookup!
  Future<String?> findNearestAirport({
    required double latitude,
    required double longitude,
    int radiusKm = 100,
  }) async {
    await authenticate();

    try {
      print('📍 Finding nearest airport to ($latitude, $longitude)...');

      final response = await _dio.get(
        '/v1/reference-data/locations/airports',
        options: Options(
          headers: {'Authorization': 'Bearer $_token'},
        ),
        queryParameters: {
          'latitude': latitude,
          'longitude': longitude,
          'radius': radiusKm,
          'page[limit]': 1, // Only need the closest one
          'sort': 'relevance', // Sort by relevance (distance + traffic)
        },
      );

      final data = response.data['data'] as List? ?? [];
      if (data.isEmpty) {
        print('⚠️ No airports found within ${radiusKm}km');
        return null;
      }

      final nearestAirport = data.first;
      final iataCode = nearestAirport['iataCode'] as String;
      final name = nearestAirport['name'] as String?;
      final distance = nearestAirport['distance']?['value'];

      print('✅ Found nearest airport: $iataCode${name != null ? ' ($name)' : ''}${distance != null ? ' - ${distance}km away' : ''}');
      return iataCode;
    } catch (e) {
      print('⚠️ Airport lookup failed: $e');
      return null;
    }
  }

  /// Discover all direct flight destinations from an airport
  /// Uses Airport Direct Destinations API with optional country filtering
  /// Filters to DOMESTIC ONLY (US) by default for same-day trip feasibility
  Future<List<Destination>> discoverDestinations({
    required String origin,
    required String date,
    int maxDurationHours = 4,
    bool domesticOnly = true, // Filter to domestic US flights only
  }) async {
    await authenticate();

    try {
      print('🔍 Discovering direct destinations from $origin (domestic only: $domesticOnly)...');

      // Build query parameters - use API's arrivalCountryCode for filtering
      final queryParams = {
        'departureAirportCode': origin,
        if (domesticOnly) 'arrivalCountryCode': 'US', // Use API filter for US domestic!
      };

      final response = await _dio.get(
        '/v1/airport/direct-destinations',
        options: Options(
          headers: {'Authorization': 'Bearer $_token'},
        ),
        queryParameters: queryParams,
      );

      final data = response.data['data'] as List? ?? [];

      // Parse destinations with geographic coordinates
      final destinations = data.map((item) {
        final geoCode = item['geoCode'] as Map<String, dynamic>?;
        return Destination(
          code: item['iataCode'] as String,
          city: item['name'] as String,
          latitude: geoCode?['latitude'] as double?,
          longitude: geoCode?['longitude'] as double?,
        );
      }).toList();

      print('✅ Found ${destinations.length} ${domesticOnly ? 'domestic US' : 'total'} destinations');
      return destinations;
    } catch (e) {
      print('⚠️ Airport Direct Destinations API failed: $e');
      return [];
    }
  }

  /// Airport & City search for autocomplete
  Future<List<Destination>> searchAirports({
    required String keyword,
    int limit = 10,
  }) async {
    if (keyword.trim().isEmpty) return [];
    await authenticate();

    try {
      final response = await _dio.get(
        '/v1/reference-data/locations',
        options: Options(
          headers: {'Authorization': 'Bearer $_token'},
        ),
        queryParameters: {
          'subType': 'AIRPORT',
          'keyword': keyword,
          'page[limit]': limit,
          'sort': 'analytics.travelers.score',
          'view': 'FULL',
        },
      );

      final data = response.data['data'] as List? ?? [];
      return data.map<Destination>((item) {
        final address = item['address'] as Map<String, dynamic>? ?? {};
        final cityName = item['cityName'] as String? ?? '';
        final country = address['countryCode'] as String? ?? '';
        final tzOffset = item['timeZoneOffset'] as String?;
        return Destination(
          code: item['iataCode'] as String,
          city: cityName.isNotEmpty ? '$cityName, $country' : item['name'] as String? ?? item['iataCode'] as String,
          latitude: (item['geoCode']?['latitude'] as num?)?.toDouble(),
          longitude: (item['geoCode']?['longitude'] as num?)?.toDouble(),
          timezoneOffset: tzOffset,
        );
      }).toList();
    } catch (e) {
      print('❌ Airport search failed: $e');
      return [];
    }
  }

  /// Search for flights between two airports on a specific date
  Future<List<FlightOffer>> searchFlights({
    required String origin,
    required String destination,
    required String date,
    int maxResults = 50,
  }) async {
    await authenticate();

    try {
      final response = await _dio.get(
        '/v2/shopping/flight-offers',
        options: Options(
          headers: {'Authorization': 'Bearer $_token'},
        ),
        queryParameters: {
          'originLocationCode': origin,
          'destinationLocationCode': destination,
          'departureDate': date,
          'adults': 1,
          'max': maxResults,
          'currencyCode': 'USD',
        },
      );

      final data = response.data['data'] as List? ?? [];
      return data.map((item) => FlightOffer.fromJson(item)).toList();
    } catch (e) {
      print('⚠️ Flight search failed for $origin->$destination: $e');
      return [];
    }
  }

  /// Filter outbound flights (early morning departures)
  List<FlightOffer> filterOutboundFlights(
    List<FlightOffer> flights,
    int maxDepartHour,
    int minDuration,
    int maxDuration,
  ) {
    final filtered = flights.where((flight) {
      // Use local hour extracted from API string (avoids timezone conversion issues)
      final passesTime = flight.departHourLocal < maxDepartHour;
      final passesDuration = flight.durationMinutes >= minDuration &&
          flight.durationMinutes <= maxDuration;

      print('      Flight ${flight.flightNumbers}: depart ${flight.departHourLocal}:xx (want <${maxDepartHour}), ${flight.durationMinutes}min (want <=${maxDuration}) - ${passesTime && passesDuration ? "PASS" : "FAIL"}');

      return passesTime && passesDuration;
    }).toList();

    return filtered;
  }

  /// Filter return flights (evening arrivals)
  List<FlightOffer> filterReturnFlights(
    List<FlightOffer> flights,
    int minArriveHour,
    int maxArriveHour,
    int minDuration,
    int maxDuration,
  ) {
    final filtered = flights.where((flight) {
      // Use local hour extracted from API string (avoids timezone conversion issues)
      final afterMin = flight.arriveHourLocal > minArriveHour ||
          flight.arriveHourLocal == minArriveHour;
      final beforeMax = flight.arriveHourLocal < maxArriveHour ||
          (flight.arriveHourLocal == maxArriveHour &&
              flight.arriveMinuteLocal <= 0);
      final passesArrivalWindow = afterMin && beforeMax;
      final passesDuration = flight.durationMinutes >= minDuration &&
          flight.durationMinutes <= maxDuration;

      final arriveText = '${flight.arriveHourLocal}:${flight.arriveMinuteLocal.toString().padLeft(2, '0')}';
      print('      Return Flight ${flight.flightNumbers}: arrive $arriveText (want ${minArriveHour}:00-${maxArriveHour}:00), ${flight.durationMinutes}min (want <=${maxDuration}) - ${passesArrivalWindow && passesDuration ? "PASS" : "FAIL"}');

      return passesArrivalWindow && passesDuration;
    }).toList();

    return filtered;
  }

  /// Calculate ground time between landing and takeoff in hours
  double calculateGroundTime(DateTime arrival, DateTime departure) {
    return departure.difference(arrival).inSeconds / 3600.0;
  }

  /// Format duration in minutes to "Xh YYm"
  String formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours}h ${mins.toString().padLeft(2, '0')}m';
  }

  /// Format time as "HH:MM"
  String formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
