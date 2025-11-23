import 'dart:async';
import 'dart:math';
import '../models/trip.dart';
import '../models/flight_offer.dart';
import 'amadeus_service.dart';
import 'duffel_service.dart';

/// Service for finding same-day trips - Pure Dart, no Flask required!
class TripSearchService {
  final AmadeusService _amadeus = AmadeusService();
  final DuffelService _duffel = DuffelService();
  static const Map<String, List<String>> _metroExpansions = {
    'NYC': ['JFK', 'LGA', 'EWR'],
    'WAS': ['DCA', 'IAD', 'BWI'],
    'CHI': ['ORD', 'MDW'],
    'HOU': ['IAH', 'HOU'],
    'LON': ['LHR', 'LGW', 'LCY', 'LTN', 'STN', 'SEN'],
    'PAR': ['CDG', 'ORY', 'BVA'],
    'BER': ['BER'],
  };

  /// Search for all viable same-day trips with PROGRESSIVE RESULTS
  /// Returns a stream that emits trips as they're found
  Stream<Trip> searchTripsStream(SearchCriteria criteria) async* {
    print('dYs? Starting same-day trip search from ${criteria.origin}');
    print('dY". Date: ${criteria.date}');
    print('⚠️ Depart by: ${criteria.departBy}:00, Return: ${criteria.returnAfter}:00-${criteria.returnBy}:00');
    print('⚡️ Flight duration limits: ${criteria.minDuration}-${criteria.maxDuration} minutes');

    // Step 1: Discover or use provided destinations
    List<Destination> destinations;
    if (criteria.destinations != null && criteria.destinations!.isNotEmpty) {
      destinations = criteria.destinations!
          .map((code) => Destination(code: code, city: code))
          .toList();
      destinations = _expandMetroDestinations(destinations);
      print('dY"? Using ${destinations.length} specified destinations (after metro expansion)');
    } else {
      destinations = await _amadeus.discoverDestinations(
        origin: criteria.origin,
        date: criteria.date,
        maxDurationHours: 4,
      );
      destinations = _expandMetroDestinations(destinations);
      print('dY"? Discovered ${destinations.length} destinations (after metro expansion)');
    }

    if (destinations.isEmpty) {
      print('❌ No destinations found');
      return;
    }

// Step 1.5: Sort destinations by distance (closest first) for faster results!
    destinations = _sortDestinationsByDistance(criteria.origin, destinations);

    // Step 2: Search destinations with rate limiting - EMIT RESULTS AS FOUND
    print('⚡ Searching ${destinations.length} destinations (streaming results)...');

    // Optimized batching: 20 requests per batch, 10 second delay between batches
    const batchSize = 20;
    for (var i = 0; i < destinations.length; i += batchSize) {
      final batch = destinations.skip(i).take(batchSize).toList();

      print('  📦 Batch ${(i ~/ batchSize) + 1}/${(destinations.length / batchSize).ceil()}: Searching ${batch.length} destinations...');

      // Search batch in parallel
      final batchFutures = batch.map((dest) =>
          _searchDestination(dest, criteria)
      ).toList();

      final batchResults = await Future.wait(batchFutures);

      // EMIT TRIPS AS SOON AS BATCH COMPLETES
      for (final trips in batchResults) {
        for (final trip in trips) {
          yield trip; // Stream each trip immediately!
        }
      }

      // 10 second delay between batches to avoid rate limiting
      if (i + batchSize < destinations.length) {
        final nextBatchNum = (i ~/ batchSize) + 2;
        print('  ⏳ Waiting 10s before batch $nextBatchNum (rate limit: 120 req/60s)...');
        await Future.delayed(Duration(seconds: 10));
      }
    }

    print('✅ Search complete - all results streamed');
  }

  /// Search for all viable same-day trips (LEGACY - returns all at once)
  /// This is the main entry point - replaces the Flask /api/search endpoint
  Future<List<Trip>> searchTrips(SearchCriteria criteria) async {
    print('dYs? Starting same-day trip search from ${criteria.origin}');
    print('dY". Date: ${criteria.date}');
    print('⚠️ Depart by: ${criteria.departBy}:00, Return: ${criteria.returnAfter}:00-${criteria.returnBy}:00');
    print('⚡️ Flight duration limits: ${criteria.minDuration}-${criteria.maxDuration} minutes');

    // Step 1: Discover or use provided destinations
    List<Destination> destinations;
    if (criteria.destinations != null && criteria.destinations!.isNotEmpty) {
      destinations = criteria.destinations!
          .map((code) => Destination(code: code, city: code))
          .toList();
      destinations = _expandMetroDestinations(destinations);
      print('dY"? Using ${destinations.length} specified destinations (after metro expansion)');
    } else {
      destinations = await _amadeus.discoverDestinations(
        origin: criteria.origin,
        date: criteria.date,
        maxDurationHours: 4,
      );
      destinations = _expandMetroDestinations(destinations);
      print('dY"? Discovered ${destinations.length} destinations (after metro expansion)');
    }

    if (destinations.isEmpty) {
      print('❌ No destinations found');
      return [];
    }

// Step 1.5: Sort destinations by distance (closest first) for faster results!
    destinations = _sortDestinationsByDistance(criteria.origin, destinations);

    // Step 2: Search destinations with rate limiting (120 requests per 60 seconds)
    print('⚡ Searching ${destinations.length} destinations (rate limit: 120 req/60s)...');
    final allTrips = <Trip>[];

    // Optimized batching: 20 requests per batch, 10 second delay between batches
    // This gives us 120 requests per minute, matching Duffel's rate limit
    const batchSize = 20;
    for (var i = 0; i < destinations.length; i += batchSize) {
      final batch = destinations.skip(i).take(batchSize).toList();

      print('  📦 Batch ${(i ~/ batchSize) + 1}/${(destinations.length / batchSize).ceil()}: Searching ${batch.length} destinations...');

      // Search batch in parallel
      final batchFutures = batch.map((dest) =>
          _searchDestination(dest, criteria)
      ).toList();

      final batchResults = await Future.wait(batchFutures);
      allTrips.addAll(batchResults.expand((trips) => trips));

      // 10 second delay between batches to avoid rate limiting
      if (i + batchSize < destinations.length) {
        final nextBatchNum = (i ~/ batchSize) + 2;
        print('  ⏳ Waiting 10s before batch $nextBatchNum (rate limit: 120 req/60s)...');
        await Future.delayed(Duration(seconds: 10));
      }
    }

    print('✅ Found ${allTrips.length} viable same-day trips');
    return allTrips;
  }

  /// Search a single destination for viable trips
  Future<List<Trip>> _searchDestination(
    Destination destination,
    SearchCriteria criteria,
  ) async {
    try {
      print('  🔍 ${destination.code} - ${destination.city}');

      // Use Duffel for ROUND-TRIP search (more efficient + better airline coverage)
      final roundTripResult = await _duffel.searchRoundTrip(
        origin: criteria.origin,
        destination: destination.code,
        date: criteria.date,
        returnDate: criteria.returnDate, // Pass return date for overnight trips
        earliestDepartHour: criteria.earliestDepart,
        departByHour: criteria.departBy,
        returnAfterHour: criteria.returnAfter,
        returnByHour: criteria.returnBy,
        minDurationMinutes: criteria.minDuration,
        maxDurationMinutes: criteria.maxDuration,
      );

      if (roundTripResult == null || roundTripResult.trips.isEmpty) {
        return [];
      }

      print('    ✅ Duffel found ${roundTripResult.trips.length} viable trips to ${destination.code}');

      // Convert Duffel RoundTripOffers to our Trip model
      final trips = roundTripResult.trips.map((offer) {
        // Calculate ground time
        final groundTimeHours = _amadeus.calculateGroundTime(
          offer.outbound.arriveTime,
          offer.returnFlight.departTime,
        );

        // DEBUG: Print ground time details
        print('    🕐 ${destination.code}: Arrive ${_amadeus.formatTime(offer.outbound.arriveTime)}, Depart ${_amadeus.formatTime(offer.returnFlight.departTime)} → Ground time: ${groundTimeHours.toStringAsFixed(2)}h (need ${criteria.minGroundTime}h)');

        // Double check ground time (Duffel search doesn't filter by min ground time)
        if (groundTimeHours < criteria.minGroundTime) {
          print('    ❌ Filtered out: ${groundTimeHours.toStringAsFixed(2)}h < ${criteria.minGroundTime}h');
          return null;
        }

        if (offer.outbound.durationMinutes < criteria.minDuration ||
            offer.returnFlight.durationMinutes < criteria.minDuration) {
          print('    ❌ Filtered out: flight time below ${criteria.minDuration} minutes');
          return null;
        }

        // Filter by allowed airlines if specified
        if (criteria.airlines != null && criteria.airlines!.isNotEmpty) {
          final outboundCarriers = offer.outbound.carriers.toSet();
          final returnCarriers = offer.returnFlight.carriers.toSet();
          final allowedAirlines = criteria.airlines!.toSet();

          final outboundMatch = outboundCarriers.any((c) => allowedAirlines.contains(c));
          final returnMatch = returnCarriers.any((c) => allowedAirlines.contains(c));

          if (!outboundMatch || !returnMatch) {
            print('    ❌ Filtered out: airlines ${outboundCarriers.union(returnCarriers)} not in allowed list ${allowedAirlines}');
            return null;
          }
        }

        return _createTrip(
          origin: criteria.origin,
          destination: destination,
          date: criteria.date,
          outbound: offer.outbound,
          returnFlight: offer.returnFlight,
          groundTimeHours: groundTimeHours,
          offerId: offer.offerId,
        );
      }).whereType<Trip>().toList();

      if (trips.isNotEmpty) {
        print('    ✨ ${trips.length} trips passed ground time check (>=${criteria.minGroundTime}h)');
      }

      return trips;
    } catch (e) {
      print('    ❌ Error searching ${destination.code}: $e');
      return [];
    }
  }

  /// Create a Trip object from flight offers
  Trip _createTrip({
    required String origin,
    required Destination destination,
    required String date,
    required FlightOffer outbound,
    required FlightOffer returnFlight,
    required double groundTimeHours,
    String? offerId,
  }) {
    final totalTripMinutes = outbound.durationMinutes +
        (groundTimeHours * 60).round() +
        returnFlight.durationMinutes;

    return Trip(
      origin: origin,
      destination: destination.code,
      city: destination.city,
      date: date,

      // Outbound
      outboundFlight: outbound.flightNumbers,
      outboundStops: outbound.numStops,
      departOrigin: _amadeus.formatTime(outbound.departTime),
      arriveDestination: _amadeus.formatTime(outbound.arriveTime),
      outboundDuration: outbound.formatDuration(),
      outboundPrice: outbound.price,

      // Return
      returnFlight: returnFlight.flightNumbers,
      returnStops: returnFlight.numStops,
      departDestination: _amadeus.formatTime(returnFlight.departTime),
      arriveOrigin: _amadeus.formatTime(returnFlight.arriveTime),
      returnDuration: returnFlight.formatDuration(),
      returnPrice: returnFlight.price,

      // Timezone offsets
      departOriginTz: outbound.departTimezoneOffset,
      arriveDestinationTz: outbound.arriveTimezoneOffset,
      departDestinationTz: returnFlight.departTimezoneOffset,
      arriveOriginTz: returnFlight.arriveTimezoneOffset,

      // Totals
      groundTimeHours: double.parse(groundTimeHours.toStringAsFixed(2)),
      groundTime: _amadeus.formatDuration((groundTimeHours * 60).round()),
      totalFlightCost: outbound.price + returnFlight.price,
      totalTripTime: _amadeus.formatDuration(totalTripMinutes),

      // Optional fields (can be populated later)
      destLat: null,
      destLng: null,
      googleFlightsUrl: _generateGoogleFlightsUrl(
        origin,
        destination.code,
        date,
        _amadeus.formatTime(outbound.departTime),
        _amadeus.formatTime(returnFlight.departTime),
      ),
      kayakUrl: _generateKayakUrl(
        origin,
        destination.code,
        date,
        _amadeus.formatTime(outbound.departTime),
        _amadeus.formatTime(returnFlight.departTime),
      ),
      airlineUrl: _generateAARewardSearchUrl(
        origin,
        destination.code,
        date,
        isOutbound: true,
      ),
      turoUrl: null,
      turoSearchUrl: _generateTuroSearchUrl(
        destination.code, // Use airport code instead of city name for better Turo location matching
        date,
        _amadeus.formatTime(outbound.arriveTime),
        _amadeus.formatTime(returnFlight.departTime),
      ),
      turoVehicle: null,
      offerId: offerId,
    );
  }

  /// Generate Google Flights URL with specific times
  String _generateGoogleFlightsUrl(
    String origin,
    String dest,
    String date,
    String outboundTime,
    String returnTime,
  ) {
    // Google Travel query string that reliably pre-fills round-trip
    final query =
        '$origin to $dest on $date return $date for 1 adult';
    final encoded = Uri.encodeComponent(query);
    return 'https://www.google.com/travel/flights?q=$encoded';
  }

  /// Generate Kayak URL with specific times
  String _generateKayakUrl(
    String origin,
    String dest,
    String date,
    String outboundTime,
    String returnTime,
  ) {
    // Extract hour from time (e.g., "07:30" -> "07")
    final outboundHour = outboundTime.split(':')[0];
    final returnHour = returnTime.split(':')[0];

    // Kayak uses time ranges in the URL
    // Add departure time windows (±2 hours from desired time)
    return 'https://www.kayak.com/flights/$origin-$dest/$date/$date?sort=bestflight_a&fs=dep0=${outboundHour}00-${int.parse(outboundHour) + 2}00;dep1=${returnHour}00-${int.parse(returnHour) + 2}00';
  }

  /// Generate Turo car rental search URL
  String _generateTuroSearchUrl(
    String city,
    String date,
    String pickupTime,
    String returnTime,
  ) {
    // Turo format: https://turo.com/search?location=City&startDate=YYYY-MM-DD&startTime=HH:MM&endDate=YYYY-MM-DD&endTime=HH:MM
    final params = Uri(queryParameters: {
      'location': city,
      'startDate': date,
      'startTime': pickupTime,
      'endDate': date,
      'endTime': returnTime,
    }).query;
    return 'https://turo.com/search?$params';
  }

  /// Generate American Airlines award search URL
  String _generateAARewardSearchUrl(
    String origin,
    String dest,
    String date,
    {required bool isOutbound}
  ) {
    // AA round-trip award search using two slices (outbound + return)
    final outboundSlice = '{"orig":"$origin","origNearby":false,"dest":"$dest","destNearby":false,"date":"$date"}';
    final returnSlice = '{"orig":"$dest","origNearby":false,"dest":"$origin","destNearby":false,"date":"$date"}';
    final slicesEncoded = Uri.encodeComponent('[$outboundSlice,$returnSlice]');
    return 'https://www.aa.com/booking/search?locale=en_US&pax=1&adult=1&child=0&type=RoundTrip&searchType=Award&cabin=&carriers=ALL&slices=$slicesEncoded&maxAwardSegmentAllowed=2';
  }

  /// Sort destinations by distance from origin (closest first)
  /// This ensures we search nearby airports first for faster results!
  List<Destination> _sortDestinationsByDistance(
    String originCode,
    List<Destination> destinations,
  ) {
    // Get origin coordinates from the first destination with coords, or use hardcoded fallback
    final originCoords = _getAirportCoordinates(originCode);
    if (originCoords == null) {
      print('⚠️ Could not find coordinates for $originCode, using alphabetical order');
      return destinations;
    }

    // Calculate distance to each destination and sort
    final destinationsWithDistance = destinations.where((dest) {
      return dest.latitude != null && dest.longitude != null;
    }).map((dest) {
      final distance = _calculateDistance(
        originCoords[0], originCoords[1],
        dest.latitude!, dest.longitude!,
      );
      return {'dest': dest, 'distance': distance};
    }).toList();

    // Sort by distance (closest first)
    destinationsWithDistance.sort((a, b) =>
      (a['distance'] as double).compareTo(b['distance'] as double)
    );

    final sorted = destinationsWithDistance
        .map((item) => item['dest'] as Destination)
        .toList();

    print('📏 Sorted ${sorted.length} destinations by distance (closest first)');
    if (sorted.isNotEmpty) {
      print('   Nearest: ${sorted.first.code}, Farthest: ${sorted.last.code}');
    }

    return sorted;
  }

  /// Expand metro/city codes (e.g., NYC, WAS) into individual airports
  List<Destination> _expandMetroDestinations(List<Destination> destinations) {
    final expanded = <Destination>[];
    for (final dest in destinations) {
      final upper = dest.code.toUpperCase();
      if (_metroExpansions.containsKey(upper)) {
        for (final airport in _metroExpansions[upper]!) {
          expanded.add(Destination(
            code: airport,
            city: dest.city,
            latitude: dest.latitude,
            longitude: dest.longitude,
            timezoneOffset: dest.timezoneOffset,
          ));
        }
      } else {
        expanded.add(dest);
      }
    }
    return expanded;
  }

  /// Calculate distance between two lat/lng points using Haversine formula (km)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371.0; // Earth's radius in kilometers
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);

    final c = 2 * asin(sqrt(a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * (pi / 180.0);

  /// Get coordinates for common US airports (fallback if needed)
  List<double>? _getAirportCoordinates(String code) {
    // Common US airports - add more as needed
    const airports = {
      'CLT': [35.2144, -80.9473],
      'ATL': [33.6407, -84.4277],
      'ORD': [41.9742, -87.9073],
      'DFW': [32.8998, -97.0403],
      'LAX': [33.9416, -118.4085],
      'JFK': [40.6413, -73.7781],
      'SFO': [37.6213, -122.3790],
      'MIA': [25.7959, -80.2870],
      'BOS': [42.3656, -71.0096],
      'SEA': [47.4502, -122.3088],
      'LAS': [36.0840, -115.1537],
      'PHX': [33.4352, -112.0101],
      'IAH': [29.9902, -95.3368],
      'DEN': [39.8561, -104.6737],
      'MCO': [28.4312, -81.3081],
    };
    return airports[code];
  }
}
