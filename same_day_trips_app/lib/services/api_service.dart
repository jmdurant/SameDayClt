import 'package:dio/dio.dart';
import '../models/trip.dart';
import '../models/flight_offer.dart';
import 'trip_search_service.dart';

class ApiService {
  // FLASK SERVER NO LONGER NEEDED! 🎉
  // Using direct Amadeus API calls instead

  final TripSearchService _tripSearch = TripSearchService();

  /// Search trips with PROGRESSIVE RESULTS - returns stream for real-time updates
  Stream<Trip> searchTripsStream({
    required String origin,
    required String date,
    String? returnDate, // Optional: defaults to same day
    required int earliestDepart,
    required int departBy,
    required int returnAfter,
    required int returnBy,
    required double minGroundTime,
    required int minDuration,
    required int maxDuration,
    List<String>? airlines,
    List<String>? destinations,
  }) {
    print('🚀 Streaming trip search via Amadeus API');
    print('📦 Criteria: origin=$origin, date=$date, returnDate=${returnDate ?? date}');

    // Create search criteria
    final criteria = SearchCriteria(
      origin: origin,
      date: date,
      returnDate: returnDate,
      earliestDepart: earliestDepart,
      departBy: departBy,
      returnAfter: returnAfter,
      returnBy: returnBy,
      minGroundTime: minGroundTime,
      minDuration: minDuration,
      maxDuration: maxDuration,
      airlines: airlines,
      destinations: destinations,
    );

    // Return the stream directly
    return _tripSearch.searchTripsStream(criteria);
  }

  /// Search trips (LEGACY - waits for all results before returning)
  Future<List<Trip>> searchTrips({
    required String origin,
    required String date,
    required int earliestDepart,
    required int departBy,
    required int returnAfter,
    required int returnBy,
    required double minGroundTime,
    required int minDuration,
    required int maxDuration,
    List<String>? airlines,
    List<String>? destinations,
  }) async {
    try {
      print('🚀 Searching trips directly via Amadeus API (no Flask!)');
      print('📦 Criteria: origin=$origin, date=$date');

      // Create search criteria
      final criteria = SearchCriteria(
        origin: origin,
        date: date,
        earliestDepart: earliestDepart,
        departBy: departBy,
        returnAfter: returnAfter,
        returnBy: returnBy,
        minGroundTime: minGroundTime,
        minDuration: minDuration,
        maxDuration: maxDuration,
        airlines: airlines,
        destinations: destinations,
      );

      // Search using pure Dart implementation
      final trips = await _tripSearch.searchTrips(criteria);

      print('✅ Found ${trips.length} trips');
      return trips;
    } catch (e, stackTrace) {
      print('💥 ERROR in searchTrips: $e');
      print('📍 Stack trace: $stackTrace');
      throw Exception('API Error: $e');
    }
  }
}
