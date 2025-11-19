import '../models/trip.dart';
import '../models/flight_offer.dart';
import 'amadeus_service.dart';
import 'duffel_service.dart';

/// Service for finding same-day trips - Pure Dart, no Flask required!
class TripSearchService {
  final AmadeusService _amadeus = AmadeusService();
  final DuffelService _duffel = DuffelService();

  /// Search for all viable same-day trips
  /// This is the main entry point - replaces the Flask /api/search endpoint
  Future<List<Trip>> searchTrips(SearchCriteria criteria) async {
    print('🚀 Starting same-day trip search from ${criteria.origin}');
    print('📅 Date: ${criteria.date}');
    print('⏰ Depart by: ${criteria.departBy}:00, Return: ${criteria.returnAfter}:00-${criteria.returnBy}:00');

    // Step 1: Discover or use provided destinations
    List<Destination> destinations;
    if (criteria.destinations != null && criteria.destinations!.isNotEmpty) {
      // Use user-specified destinations
      destinations = criteria.destinations!
          .map((code) => Destination(code: code, city: code))
          .toList();
      print('📍 Using ${destinations.length} specified destinations');
    } else {
      // Auto-discover destinations
      destinations = await _amadeus.discoverDestinations(
        origin: criteria.origin,
        date: criteria.date,
        maxDurationHours: 4,
      );
      print('📍 Discovered ${destinations.length} destinations');
    }

    if (destinations.isEmpty) {
      print('⚠️ No destinations found');
      return [];
    }

    // Step 2: Search destinations with optimized rate limiting for production
    print('⚡ Searching ${destinations.length} destinations (optimized for production rate limits)...');
    final allTrips = <Trip>[];

    // Process in larger batches - production allows 40 TPS vs 10 TPS in test
    const batchSize = 12; // Increased from 3 to take advantage of production limits
    for (var i = 0; i < destinations.length; i += batchSize) {
      final batch = destinations.skip(i).take(batchSize).toList();

      // Search batch in parallel
      final batchFutures = batch.map((dest) =>
          _searchDestination(dest, criteria)
      ).toList();

      final batchResults = await Future.wait(batchFutures);
      allTrips.addAll(batchResults.expand((trips) => trips));

      // Minimal delay between batches - production allows 1 request per 100ms
      if (i + batchSize < destinations.length) {
        await Future.delayed(Duration(milliseconds: 150)); // Reduced from 500ms
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
        departByHour: criteria.departBy,
        returnAfterHour: criteria.returnAfter,
        returnByHour: criteria.returnBy,
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

        // Double check ground time (Duffel search doesn't filter by min ground time)
        if (groundTimeHours < criteria.minGroundTime) {
          return null;
        }

        return _createTrip(
          origin: criteria.origin,
          destination: destination,
          date: criteria.date,
          outbound: offer.outbound,
          returnFlight: offer.returnFlight,
          groundTimeHours: groundTimeHours,
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
    // Round trip format: origin.dest.date*dest.origin.date
    final flightString = '$origin.$dest.$date*$dest.$origin.$date';

    // Add departure time filters using URL parameters
    // Format times as HHMM (e.g., "0730" for 7:30 AM)
    final outboundHHMM = outboundTime.replaceAll(':', '');
    final returnHHMM = returnTime.replaceAll(':', '');

    // Build URL with time filters
    // Note: Google Flights may not honor all these parameters, but it helps
    return 'https://www.google.com/flights?hl=en#flt=$flightString;c:USD;e:1;sd:1;t:f;tt:o;dep1:$outboundHHMM;dep2:$returnHHMM';
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
    // AA format: https://www.aa.com/booking/search?locale=en_US&pax=1&adult=1&type=OneWay&searchType=Award&slices=[{"orig":"CLT","dest":"ATL","date":"2025-11-15"}]
    final slice = '{"orig":"$origin","origNearby":false,"dest":"$dest","destNearby":false,"date":"$date"}';
    return 'https://www.aa.com/booking/search?locale=en_US&pax=1&adult=1&child=0&type=OneWay&searchType=Award&cabin=&carriers=ALL&slices=%5B$slice%5D&maxAwardSegmentAllowed=2';
  }
}
