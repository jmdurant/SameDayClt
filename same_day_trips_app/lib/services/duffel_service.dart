import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
    String? returnDate,             // Optional: defaults to same day for backward compatibility
    int earliestDepartHour = 5,     // e.g., 5 for 5 AM (EARLIEST departure)
    required int departByHour,      // e.g., 9 for 9 AM (LATEST departure)
    required int returnAfterHour,   // e.g., 15 for 3 PM (EARLIEST home arrival)
    required int returnByHour,      // e.g., 19 for 7 PM (LATEST home arrival)
    int minDurationMinutes = 50,
    int maxDurationMinutes = 240,
    int maxConnections = 1,
    List<String>? allowedCarriers,
  }) async {
    // PLATFORM DETECTION: Use Cloud Function on web, direct API on mobile
    if (kIsWeb) {
      print('  🌐 WEB: Using Cloud Function proxy for Duffel API');
      return _searchViaCloudFunction(
        origin: origin,
        destination: destination,
        date: date,
        returnDate: returnDate,
        earliestDepartHour: earliestDepartHour,
        departByHour: departByHour,
        returnAfterHour: returnAfterHour,
        returnByHour: returnByHour,
        minDurationMinutes: minDurationMinutes,
        maxDurationMinutes: maxDurationMinutes,
        allowedCarriers: allowedCarriers,
      );
    }

    // MOBILE: Use direct Duffel API
    try {
      print('  📱 MOBILE: Using direct Duffel API');
      print('  🔍 Duffel ROUND-TRIP: $origin ↔ $destination on $date');

      // Calculate earliest departure time
      final searchDate = DateTime.parse(date);
      final now = DateTime.now();
      final isToday = searchDate.year == now.year &&
                      searchDate.month == now.month &&
                      searchDate.day == now.day;

      // If searching today, start from current time + 2 hours, otherwise use user's earliest departure time
      int earliestHour = isToday
          ? (now.hour + 2).clamp(0, 23)
          : earliestDepartHour;

      // Ensure departure window is at least 1 hour to satisfy Duffel's requirement
      int latestHour = departByHour;
      if (earliestHour >= latestHour) {
        // Too late for today's search, no valid time window
        print('  ⚠️ Too late to search for today (need departure before ${departByHour}:00, earliest available is ${earliestHour}:00)');
        return null;
      }

      // Format time windows (Duffel uses HH:MM format)
      final departFrom = '${earliestHour.toString().padLeft(2, '0')}:00';
      final departTo = '${latestHour.toString().padLeft(2, '0')}:00';

      // For return, use a wide departure window and filter by actual home arrival later
      // This avoids timezone confusion with arrival_time filter
      final returnDepartFrom = '12:00'; // Earliest return departure (noon)
      final returnDepartTo = '23:59'; // Latest return departure

      print('    ⏰ Outbound: Depart $departFrom - $departTo');
      print('    ⏰ Return: Depart destination $returnDepartFrom - $returnDepartTo (filter home arrival ${returnAfterHour}:00-${returnByHour}:00 after)');

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
                'departure_date': returnDate ?? date, // Use separate return date for overnight trips
                'departure_time': {
                  'from': returnDepartFrom,
                  'to': returnDepartTo,
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

      // Parse round-trip offers with home arrival filtering
      final trips = <RoundTripOffer>[];
      for (final offer in offers) {
        final parsed = _parseRoundTripOffer(
          offer,
          minDurationMinutes,
          maxDurationMinutes,
          returnAfterHour,
          returnByHour,
          allowedCarriers,
        );
        if (parsed != null) {
          trips.add(parsed);
        }
      }

      if (trips.isEmpty) {
        print('  ⚠️ No trips matched filters (duration, home arrival time)');
        return null;
      }

      // Deduplicate trips - keep only the cheapest option for each unique flight combination
      final uniqueTrips = <String, RoundTripOffer>{};
      for (final trip in trips) {
        // Create a unique key based on flight times and numbers
        final key = '${trip.outbound.flightNumbers}_${trip.outbound.departTime}_${trip.returnFlight.flightNumbers}_${trip.returnFlight.departTime}';

        // Keep this trip if it's new or cheaper than existing one
        if (!uniqueTrips.containsKey(key) || trip.totalPrice < uniqueTrips[key]!.totalPrice) {
          uniqueTrips[key] = trip;
        }
      }

      final deduplicatedTrips = uniqueTrips.values.toList();
      print('  📋 Deduplicated: ${trips.length} offers → ${deduplicatedTrips.length} unique trips');

      return RoundTripFlights(
        origin: origin,
        destination: destination,
        trips: deduplicatedTrips,
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
  RoundTripOffer? _parseRoundTripOffer(
    Map<String, dynamic> offer,
    int minDurationMinutes,
    int maxDurationMinutes,
    int returnAfterHour,
    int returnByHour,
    List<String>? allowedCarriers,
  ) {
    try {
      final slices = offer['slices'] as List;
      if (slices.length != 2) return null; // Must have outbound + return

      final outboundSlice = slices[0] as Map<String, dynamic>;
      final returnSlice = slices[1] as Map<String, dynamic>;

      print('    🔍 PARSING ROUND-TRIP OFFER:');
      print('       Slice 0 (outbound): ${outboundSlice['origin']} → ${outboundSlice['destination']}');
      print('       Slice 1 (return): ${returnSlice['origin']} → ${returnSlice['destination']}');

      // DEBUG: Check actual segment times from Duffel for BOTH slices
      final outboundSegs = outboundSlice['segments'] as List;
      if (outboundSegs.isNotEmpty) {
        print('       🐛 BUG DEBUG - OUTBOUND slice segments:');
        for (var i = 0; i < outboundSegs.length; i++) {
          final seg = outboundSegs[i] as Map<String, dynamic>;
          print('          Segment $i: departing_at="${seg['departing_at']}", arriving_at="${seg['arriving_at']}"');
        }
      }

      final returnSegs = returnSlice['segments'] as List;
      if (returnSegs.isNotEmpty) {
        print('       🐛 BUG DEBUG - RETURN slice segments:');
        for (var i = 0; i < returnSegs.length; i++) {
          final seg = returnSegs[i] as Map<String, dynamic>;
          print('          Segment $i: departing_at="${seg['departing_at']}", arriving_at="${seg['arriving_at']}"');
        }
      }

      final outbound = _parseSliceToFlightOffer(outboundSlice, 'OUTBOUND');
      final returnFlight = _parseSliceToFlightOffer(returnSlice, 'RETURN');

      print('       🐛 BUG DEBUG - Parsed times:');
      print('          Outbound departTime: ${outbound?.departTime}');
      print('          Return departTime: ${returnFlight?.departTime}');

      if (outbound == null || returnFlight == null) return null;

      // Filter by allowed carriers
      if (allowedCarriers != null && allowedCarriers.isNotEmpty) {
        bool matches(List<String> carriers) =>
            carriers.any((c) => allowedCarriers.contains(c.toUpperCase()));
        if (!matches(outbound.carriers) || !matches(returnFlight.carriers)) {
          return null;
        }
      }

      // CALCULATE GROUND TIME to debug the issue
      final groundTimeSeconds = returnFlight.departTime.difference(outbound.arriveTime).inSeconds;
      final groundTimeHours = groundTimeSeconds / 3600.0;
      print('       ⏱️ Ground time: ${outbound.arriveTime} (arrive dest) → ${returnFlight.departTime} (depart dest) = ${groundTimeHours.toStringAsFixed(2)}h');

      // Filter by duration
      if (outbound.durationMinutes < minDurationMinutes ||
          returnFlight.durationMinutes < minDurationMinutes) {
        return null;
      }

      if (outbound.durationMinutes > maxDurationMinutes ||
          returnFlight.durationMinutes > maxDurationMinutes) {
        return null;
      }

      // Filter by home arrival time (return flight must arrive home between returnAfterHour and returnByHour)
      final homeArrivalHour = returnFlight.arriveHourLocal;
      final homeArrivalMinute = returnFlight.arriveMinuteLocal;
      final afterWindow = homeArrivalHour < returnAfterHour;
      final pastLatest = homeArrivalHour > returnByHour ||
          (homeArrivalHour == returnByHour && homeArrivalMinute > 0);
      if (afterWindow || pastLatest) {
        final arrivalText = '${homeArrivalHour}:${homeArrivalMinute.toString().padLeft(2, '0')}';
        print('    ! Filtered: Home arrival $arrivalText outside window $returnAfterHour:00-$returnByHour:00');
        return null;
      }

      // Get combined price
      final totalAmount = offer['total_amount'] as String;
      final totalPrice = double.parse(totalAmount);

      // Attach price to slices so downstream UI shows costs
      final pricedOutbound = outbound.copyWith(price: totalPrice / 2);
      final pricedReturn = returnFlight.copyWith(price: totalPrice / 2);

      return RoundTripOffer(
        outbound: pricedOutbound,
        returnFlight: pricedReturn,
        totalPrice: totalPrice,
        offerId: offer['id'] as String,
      );
    } catch (e) {
      print('    ⚠️ Error parsing round-trip offer: $e');
      return null;
    }
  }

  /// Parse a Duffel slice into FlightOffer
  FlightOffer? _parseSliceToFlightOffer(Map<String, dynamic> slice, [String label = 'SLICE']) {
    try {
      final segments = slice['segments'] as List;
      if (segments.isEmpty) return null;

      final firstSegment = segments.first as Map<String, dynamic>;
      final lastSegment = segments.last as Map<String, dynamic>;

      // Parse times
      final departingAt = firstSegment['departing_at'] as String;
      final departTime = DateTime.parse(departingAt);
      final departHourLocal = int.parse(departingAt.substring(11, 13));
      final departMinuteLocal = int.parse(departingAt.substring(14, 16));
      final departTzOffset = _extractTimezoneOffset(departingAt);

      final arrivingAt = lastSegment['arriving_at'] as String;
      final arriveTime = DateTime.parse(arrivingAt);
      final arriveHourLocal = int.parse(arrivingAt.substring(11, 13));
      final arriveMinuteLocal = int.parse(arrivingAt.substring(14, 16));
      final arriveTzOffset = _extractTimezoneOffset(arrivingAt);

      print('       📋 $label: departing_at="$departingAt" → parsed time=$departTime, hour=$departHourLocal');
      print('       📋 $label: arriving_at="$arrivingAt" → parsed time=$arriveTime, hour=$arriveHourLocal');

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

      final carriers = segments
          .map((seg) {
            final operating = seg['operating_carrier'] as Map<String, dynamic>?;
            final marketing = seg['marketing_carrier'] as Map<String, dynamic>?;
            return (operating?['iata_code'] ?? marketing?['iata_code'] ?? '??') as String;
          })
          .where((c) => c.isNotEmpty)
          .map((c) => c.toUpperCase())
          .toSet()
          .toList();

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
        carriers: carriers,
        departHourLocal: departHourLocal,
        arriveHourLocal: arriveHourLocal,
        departMinuteLocal: departMinuteLocal,
        arriveMinuteLocal: arriveMinuteLocal,
        departTimezoneOffset: departTzOffset,
        arriveTimezoneOffset: arriveTzOffset,
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
      final departMinuteLocal = int.parse(departingAt.substring(14, 16));

      // Parse arrival time from last segment
      final arrivingAt = lastSegment['arriving_at'] as String;
      final arriveTime = DateTime.parse(arrivingAt);
      final arriveHourLocal = int.parse(arrivingAt.substring(11, 13));
      final arriveMinuteLocal = int.parse(arrivingAt.substring(14, 16));

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

      final carriers = segments
          .map((seg) {
            final operating = seg['operating_carrier'] as Map<String, dynamic>?;
            final marketing = seg['marketing_carrier'] as Map<String, dynamic>?;
            return (operating?['iata_code'] ?? marketing?['iata_code'] ?? '??') as String;
          })
          .where((c) => c.isNotEmpty)
          .map((c) => c.toUpperCase())
          .toSet()
          .toList();

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
        carriers: carriers,
        departHourLocal: departHourLocal,
        arriveHourLocal: arriveHourLocal,
        departMinuteLocal: departMinuteLocal,
        arriveMinuteLocal: arriveMinuteLocal,
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
    int minDuration,
    int maxDuration,
  ) {
    final filtered = flights.where((flight) {
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

  /// Extract timezone offset from ISO 8601 timestamp
  /// Example: "2025-11-15T07:35:00-05:00" -> "-05:00"
  String? _extractTimezoneOffset(String isoTimestamp) {
    // ISO 8601 format: YYYY-MM-DDTHH:MM:SS±HH:MM
    // Offset starts at position 19
    if (isoTimestamp.length >= 25) {
      return isoTimestamp.substring(19); // e.g., "-05:00" or "+01:00"
    }
    return null;
  }

  /// WEB ONLY: Search via Firebase Cloud Function (avoids CORS issues)
  Future<RoundTripFlights?> _searchViaCloudFunction({
    required String origin,
    required String destination,
    required String date,
    String? returnDate,
    int earliestDepartHour = 5,
    required int departByHour,
    required int returnAfterHour,
    required int returnByHour,
    int minDurationMinutes = 50,
    int maxDurationMinutes = 240,
    List<String>? allowedCarriers,
  }) async {
    try {
      const functionUrl = 'https://us-central1-samedaytrips.cloudfunctions.net/duffelProxy';

      final dio = Dio(); // Use clean Dio instance for Cloud Function
      final response = await dio.post(
        functionUrl,
        data: {
          'origin': origin,
          'destination': destination,
          'date': date,
          if (returnDate != null) 'returnDate': returnDate, // Only include if different from departure
          'earliestDepartHour': earliestDepartHour,
          'departByHour': departByHour,
          'returnAfterHour': returnAfterHour,
          'returnByHour': returnByHour,
          'minDurationMinutes': minDurationMinutes,
          'maxDurationMinutes': maxDurationMinutes,
          'allowedCarriers': allowedCarriers,
        },
      );

      if (response.statusCode != 200) {
        print('  ❌ Cloud Function error: ${response.statusCode}');
        return null;
      }

      final data = response.data as Map<String, dynamic>;
      final trips = data['trips'] as List? ?? [];

      if (trips.isEmpty) {
        print('  ⚠️ Cloud Function returned 0 trips');
        return null;
      }

      print('  ✅ Cloud Function returned ${trips.length} trips');

      final filteredTrips = trips.where((trip) {
        final outbound = trip['outbound'] as Map<String, dynamic>?;
        final returnFlight = trip['returnFlight'] as Map<String, dynamic>?;
        if (outbound == null || returnFlight == null) return false;

        final outboundDuration = (outbound['durationMinutes'] as num?)?.toInt() ?? 0;
        final returnDuration = (returnFlight['durationMinutes'] as num?)?.toInt() ?? 0;

        final meetsMin = outboundDuration >= minDurationMinutes &&
            returnDuration >= minDurationMinutes;
        final withinMax = outboundDuration <= maxDurationMinutes &&
            returnDuration <= maxDurationMinutes;

        bool matchesCarrier(List<dynamic>? carriers) {
          if (allowedCarriers == null || allowedCarriers.isEmpty) return true;
          final codes = carriers
                  ?.map((c) => c.toString().toUpperCase())
                  .where((c) => c.isNotEmpty)
                  .toList() ??
              [];
          return codes.any((c) => allowedCarriers.contains(c));
        }

        final outboundCarriers = outbound['carriers'] as List<dynamic>?;
        final returnCarriers = returnFlight['carriers'] as List<dynamic>?;
        final carriersOk = matchesCarrier(outboundCarriers) && matchesCarrier(returnCarriers);

        return meetsMin && withinMax && carriersOk;
      }).toList();

      if (filteredTrips.isEmpty) {
        print('  ⚠️ Cloud Function trips filtered out by duration (min $minDurationMinutes, max $maxDurationMinutes)');
        return null;
      }

      // Parse Cloud Function response format to our RoundTripOffer format
      final parsedTrips = filteredTrips.map((trip) {
        final outbound = trip['outbound'] as Map<String, dynamic>;
        final returnFlight = trip['returnFlight'] as Map<String, dynamic>;
        final outboundCarriers = (outbound['carriers'] as List<dynamic>? ?? [])
            .map((c) => c.toString())
            .toList();
        final returnCarriers = (returnFlight['carriers'] as List<dynamic>? ?? [])
            .map((c) => c.toString())
            .toList();

        return RoundTripOffer(
          outbound: FlightOffer(
            departTime: DateTime.parse(outbound['departTime']),
            arriveTime: DateTime.parse(outbound['arriveTime']),
            durationMinutes: outbound['durationMinutes'] as int,
            flightNumbers: outbound['flightNumbers'] as String,
            numStops: outbound['numStops'] as int,
            price: (trip['totalPrice'] as num).toDouble() / 2, // Split price
            carriers: outboundCarriers,
            departHourLocal: DateTime.parse(outbound['departTime']).hour,
            arriveHourLocal: DateTime.parse(outbound['arriveTime']).hour,
            departMinuteLocal: DateTime.parse(outbound['departTime']).minute,
            arriveMinuteLocal: DateTime.parse(outbound['arriveTime']).minute,
          ),
          returnFlight: FlightOffer(
            departTime: DateTime.parse(returnFlight['departTime']),
            arriveTime: DateTime.parse(returnFlight['arriveTime']),
            durationMinutes: returnFlight['durationMinutes'] as int,
            flightNumbers: returnFlight['flightNumbers'] as String,
            numStops: returnFlight['numStops'] as int,
            price: (trip['totalPrice'] as num).toDouble() / 2, // Split price
            carriers: returnCarriers,
            departHourLocal: DateTime.parse(returnFlight['departTime']).hour,
            arriveHourLocal: DateTime.parse(returnFlight['arriveTime']).hour,
            departMinuteLocal: DateTime.parse(returnFlight['departTime']).minute,
            arriveMinuteLocal: DateTime.parse(returnFlight['arriveTime']).minute,
          ),
          totalPrice: (trip['totalPrice'] as num).toDouble(),
          offerId: trip['offerId'] as String,
        );
      }).toList();

      return RoundTripFlights(
        origin: origin,
        destination: destination,
        trips: parsedTrips,
      );
    } catch (e) {
      print('  ❌ Cloud Function call failed: $e');
      if (e is DioException && e.response != null) {
        print('  Response: ${e.response?.data}');
      }
      return null;
    }
  }

  /// Create a Duffel checkout link via Cloud Function so secrets stay server-side
  Future<String?> createDuffelLink({
    required String offerId,
    String? email,
    String? phoneNumber,
    String? givenName,
    String? familyName,
  }) async {
    try {
      const functionUrl = 'https://createduffellink-yz6dw3fkaa-uc.a.run.app';
      final dio = Dio();

      final response = await dio.post(functionUrl, data: {
        'offerId': offerId,
        if (email != null) 'email': email,
        if (phoneNumber != null) 'phoneNumber': phoneNumber,
        if (givenName != null) 'givenName': givenName,
        if (familyName != null) 'familyName': familyName,
      });

      if (response.statusCode != 200) {
        print('  ? Duffel link error: ${response.statusCode}');
        return null;
      }

      final data = response.data as Map<String, dynamic>;
      final linkUrl = data['linkUrl'] as String?
          ?? data['url'] as String?
          ?? data['link'] as String?
          ?? data['data']?['url'] as String?;
      return linkUrl;
    } catch (e) {
      print('  ? Failed to create Duffel link: $e');
      if (e is DioException && e.response != null) {
        print('  Response: ${e.response?.data}');
      }
      return null;
    }
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
