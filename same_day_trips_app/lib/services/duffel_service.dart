import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/flight_offer.dart';

/// Duffel API service - supports ALL airlines including Delta & American!
class DuffelService {
  static const String baseUrl = 'https://api.duffel.com';
  static String get accessToken => dotenv.env['DUFFEL_ACCESS_TOKEN'] ?? '';

  final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Accept-Encoding': 'gzip',
      'Duffel-Version': 'v2',
    },
  ));

  /// Note: Duffel doesn't have a built-in destination discovery API.
  /// Use AmadeusService.discoverDestinations() for route discovery,
  /// then use DuffelService.searchFlights() for actual flight searches.
  /// This hybrid approach gives you:
  ///   - Accurate route discovery (Amadeus knows actual direct flights)
  ///   - Full airline coverage (Duffel includes Delta & American)

  /// Search for ROUND-TRIP flights with time windows (OPTIMIZED!)
  /// This is 50% more efficient than two one-way searches
  Future<RoundTripFlights?> searchRoundTrip({
    required String origin,
    required String destination,
    required String date,
    required int departByHour,      // e.g., 9 for 9 AM
    required int returnAfterHour,   // e.g., 15 for 3 PM
    required int returnByHour,      // e.g., 19 for 7 PM
    int maxDurationMinutes = 240,
    int maxConnections = 1,
  }) async {
    try {
      print('  🔍 Duffel ROUND-TRIP: $origin ↔ $destination on $date');

      // Format time windows (Duffel uses HH:MM format)
      final departFrom = '05:00'; // Start of morning
      final departTo = '${departByHour.toString().padLeft(2, '0')}:00';
      final returnFrom = '${returnAfterHour.toString().padLeft(2, '0')}:00';
      final returnTo = '${returnByHour.toString().padLeft(2, '0')}:00';

      print('    ⏰ Outbound: $departFrom - $departTo');
      print('    ⏰ Return: $returnFrom - $returnTo');

      final response = await _dio.post(
        '/air/offer_requests',
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
        ),
        data: {
          'data': {
            'slices': [
              {
                'origin': origin,
                'destination': destination,
                'departure_date': date,
                'departure_time': {
                  'from': departFrom,
                  'to': departTo,
                }
              },
              {
                'origin': destination,  // Return flight
                'destination': origin,
                'departure_date': date,
                'departure_time': {
                  'from': returnFrom,
                  'to': returnTo,
                }
              }
            ],
            'passengers': [
              {'type': 'adult'}
            ],
            'cabin_class': 'economy',
            'max_connections': maxConnections,
            'return_offers': true,
          }
        },
      );

      final data = response.data['data'] as Map<String, dynamic>;
      final offers = data['offers'] as List? ?? [];

      print('  ✅ Duffel returned ${offers.length} round-trip offers');

      if (offers.isEmpty) {
        return null;
      }

      // Parse round-trip offers
      final trips = <RoundTripOffer>[];
      for (final offer in offers) {
        final parsed = _parseRoundTripOffer(offer, maxDurationMinutes);
        if (parsed != null) {
          trips.add(parsed);
        }
      }

      if (trips.isEmpty) {
        print('  ⚠️ No trips matched duration filter (<=$maxDurationMinutes min)');
        return null;
      }

      return RoundTripFlights(
        origin: origin,
        destination: destination,
        trips: trips,
      );
    } catch (e) {
      print('  ⚠️ Duffel round-trip error for $origin↔$destination: $e');
      if (e is DioException && e.response != null) {
        print('  Response: ${e.response?.data}');
      }
      return null;
    }
  }

  /// Parse a round-trip offer from Duffel
  RoundTripOffer? _parseRoundTripOffer(Map<String, dynamic> offer, int maxDurationMinutes) {
    try {
      final slices = offer['slices'] as List;
      if (slices.length != 2) return null; // Must have outbound + return

      final outboundSlice = slices[0] as Map<String, dynamic>;
      final returnSlice = slices[1] as Map<String, dynamic>;

      final outbound = _parseSliceToFlightOffer(outboundSlice);
      final returnFlight = _parseSliceToFlightOffer(returnSlice);

      if (outbound == null || returnFlight == null) return null;

      // Filter by duration
      if (outbound.durationMinutes > maxDurationMinutes ||
          returnFlight.durationMinutes > maxDurationMinutes) {
        return null;
      }

      // Get combined price
      final totalAmount = offer['total_amount'] as String;
      final totalPrice = double.parse(totalAmount);

      return RoundTripOffer(
        outbound: outbound,
        returnFlight: returnFlight,
        totalPrice: totalPrice,
        offerId: offer['id'] as String,
      );
    } catch (e) {
      print('    ⚠️ Error parsing round-trip offer: $e');
      return null;
    }
  }

  /// Parse a Duffel slice into FlightOffer
  FlightOffer? _parseSliceToFlightOffer(Map<String, dynamic> slice) {
    try {
      final segments = slice['segments'] as List;
      if (segments.isEmpty) return null;

      final firstSegment = segments.first as Map<String, dynamic>;
      final lastSegment = segments.last as Map<String, dynamic>;

      // Parse times
      final departingAt = firstSegment['departing_at'] as String;
      final departTime = DateTime.parse(departingAt);
      final departHourLocal = int.parse(departingAt.substring(11, 13));

      final arrivingAt = lastSegment['arriving_at'] as String;
      final arriveTime = DateTime.parse(arrivingAt);
      final arriveHourLocal = int.parse(arrivingAt.substring(11, 13));

      // Duration
      final durationStr = slice['duration'] as String?;
      final durationMinutes = durationStr != null
          ? _parseDuration(durationStr)
          : arriveTime.difference(departTime).inMinutes;

      // Flight numbers
      final flightNumbers = segments
          .map((seg) {
            final operating = seg['operating_carrier'] as Map<String, dynamic>?;
            final marketing = seg['marketing_carrier'] as Map<String, dynamic>?;
            final carrier = operating?['iata_code'] ?? marketing?['iata_code'] ?? '??';
            final number = seg['operating_carrier_flight_number'] ??
                          seg['marketing_carrier_flight_number'] ?? '???';
            return '$carrier$number';
          })
          .join(', ');

      final numStops = segments.length - 1;

      // Note: Price is at offer level, not slice level
      // We'll use 0.0 here and set it from the offer's total_amount
      return FlightOffer(
        departTime: departTime,
        arriveTime: arriveTime,
        durationMinutes: durationMinutes,
        flightNumbers: flightNumbers,
        numStops: numStops,
        price: 0.0, // Will be set from round-trip total
        departHourLocal: departHourLocal,
        arriveHourLocal: arriveHourLocal,
      );
    } catch (e) {
      print('    ⚠️ Error parsing slice: $e');
      return null;
    }
  }

  /// Search for flights using Duffel's Offer Request API (ONE-WAY)
  Future<List<FlightOffer>> searchFlights({
    required String origin,
    required String destination,
    required String date,
    int maxResults = 50,
  }) async {
    try {
      print('  🔍 Duffel: Searching $origin → $destination on $date');

      final response = await _dio.post(
        '/air/offer_requests',
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
        ),
        data: {
          'data': {
            'slices': [
              {
                'origin': origin,
                'destination': destination,
                'departure_date': date,
              }
            ],
            'passengers': [
              {'type': 'adult'}
            ],
            'cabin_class': 'economy',
            'max_connections': 1, // Allow up to 1 stop
            'return_offers': true,
          }
        },
      );

      final data = response.data['data'] as Map<String, dynamic>;
      final offers = data['offers'] as List? ?? [];

      print('  ✅ Duffel returned ${offers.length} offers');

      // Convert Duffel offers to FlightOffer objects
      return offers
          .map((offer) => _parseDuffelOffer(offer))
          .whereType<FlightOffer>() // Filter out nulls from parsing errors
          .take(maxResults)
          .toList();
    } catch (e) {
      print('  ⚠️ Duffel API error for $origin->$destination: $e');
      if (e is DioException && e.response != null) {
        print('  Response: ${e.response?.data}');
      }
      return [];
    }
  }

  /// Parse a Duffel offer into our FlightOffer model
  FlightOffer? _parseDuffelOffer(Map<String, dynamic> offer) {
    try {
      final slices = offer['slices'] as List;
      if (slices.isEmpty) return null;

      final slice = slices[0] as Map<String, dynamic>;
      final segments = slice['segments'] as List;
      if (segments.isEmpty) return null;

      final firstSegment = segments.first as Map<String, dynamic>;
      final lastSegment = segments.last as Map<String, dynamic>;

      // Parse departure time from first segment
      final departingAt = firstSegment['departing_at'] as String;
      final departTime = DateTime.parse(departingAt);
      final departHourLocal = int.parse(departingAt.substring(11, 13));

      // Parse arrival time from last segment
      final arrivingAt = lastSegment['arriving_at'] as String;
      final arriveTime = DateTime.parse(arrivingAt);
      final arriveHourLocal = int.parse(arrivingAt.substring(11, 13));

      // Calculate duration in minutes
      final durationStr = slice['duration'] as String?;
      final durationMinutes = durationStr != null
          ? _parseDuration(durationStr)
          : arriveTime.difference(departTime).inMinutes;

      // Get flight numbers (carrier code + flight number)
      final flightNumbers = segments
          .map((seg) {
            final operating = seg['operating_carrier'] as Map<String, dynamic>?;
            final marketing = seg['marketing_carrier'] as Map<String, dynamic>?;
            final carrier = operating?['iata_code'] ?? marketing?['iata_code'] ?? '??';
            final number = seg['operating_carrier_flight_number'] ??
                          seg['marketing_carrier_flight_number'] ?? '???';
            return '$carrier$number';
          })
          .join(', ');

      // Number of stops (segments - 1)
      final numStops = segments.length - 1;

      // Price
      final totalAmount = offer['total_amount'] as String;
      final price = double.parse(totalAmount);

      return FlightOffer(
        departTime: departTime,
        arriveTime: arriveTime,
        durationMinutes: durationMinutes,
        flightNumbers: flightNumbers,
        numStops: numStops,
        price: price,
        departHourLocal: departHourLocal,
        arriveHourLocal: arriveHourLocal,
      );
    } catch (e) {
      print('    ⚠️ Error parsing Duffel offer: $e');
      return null;
    }
  }

  /// Parse ISO 8601 duration format: "PT2H15M" -> 135 minutes
  int _parseDuration(String duration) {
    int hours = 0;
    int minutes = 0;

    final hourMatch = RegExp(r'(\d+)H').firstMatch(duration);
    final minMatch = RegExp(r'(\d+)M').firstMatch(duration);

    if (hourMatch != null) {
      hours = int.parse(hourMatch.group(1)!);
    }
    if (minMatch != null) {
      minutes = int.parse(minMatch.group(1)!);
    }

    return hours * 60 + minutes;
  }

  /// Filter outbound flights (early morning departures)
  List<FlightOffer> filterOutboundFlights(
    List<FlightOffer> flights,
    int maxDepartHour,
    int maxDuration,
  ) {
    final filtered = flights.where((flight) {
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

/// Round-trip flight search results
class RoundTripFlights {
  final String origin;
  final String destination;
  final List<RoundTripOffer> trips;

  RoundTripFlights({
    required this.origin,
    required this.destination,
    required this.trips,
  });
}

/// A single round-trip offer (outbound + return)
class RoundTripOffer {
  final FlightOffer outbound;
  final FlightOffer returnFlight;
  final double totalPrice;  // Combined round-trip price
  final String offerId;     // Duffel offer ID for booking

  RoundTripOffer({
    required this.outbound,
    required this.returnFlight,
    required this.totalPrice,
    required this.offerId,
  });
}
