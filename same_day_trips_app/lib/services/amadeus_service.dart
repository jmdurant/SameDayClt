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

  /// Discover all direct flight destinations from an airport
  /// Uses Airport Direct Destinations API
  Future<List<Destination>> discoverDestinations({
    required String origin,
    required String date,
    int maxDurationHours = 4,
  }) async {
    await authenticate();

    try {
      print('🔍 Discovering direct destinations from $origin...');

      final response = await _dio.get(
        '/v1/airport/direct-destinations',
        options: Options(
          headers: {'Authorization': 'Bearer $_token'},
        ),
        queryParameters: {
          'departureAirportCode': origin,
        },
      );

      final data = response.data['data'] as List? ?? [];
      final destinations = data.map((item) {
        return Destination(
          code: item['iataCode'] as String,
          city: item['name'] as String,
        );
      }).toList();

      print('✅ Found ${destinations.length} direct destinations');
      return destinations;
    } catch (e) {
      print('⚠️ Airport Direct Destinations API failed: $e');
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
    int maxDuration,
  ) {
    final filtered = flights.where((flight) {
      // Use local hour extracted from API string (avoids timezone conversion issues)
      final passesTime = flight.departHourLocal < maxDepartHour;
      final passesDuration = flight.durationMinutes <= maxDuration;

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
    int maxDuration,
  ) {
    final filtered = flights.where((flight) {
      // Use local hour extracted from API string (avoids timezone conversion issues)
      final passesArrivalWindow = flight.arriveHourLocal >= minArriveHour &&
                                   flight.arriveHourLocal < maxArriveHour;
      final passesDuration = flight.durationMinutes <= maxDuration;

      print('      Return Flight ${flight.flightNumbers}: arrive ${flight.arriveHourLocal}:xx (want ${minArriveHour}-${maxArriveHour}), ${flight.durationMinutes}min (want <=${maxDuration}) - ${passesArrivalWindow && passesDuration ? "PASS" : "FAIL"}');

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
