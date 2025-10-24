import 'package:dio/dio.dart';
import '../models/trip.dart';
import '../models/flight_offer.dart';
import 'trip_search_service.dart';

class ApiService {
  // FLASK SERVER NO LONGER NEEDED! 🎉
  // Using direct Amadeus API calls instead

  final TripSearchService _tripSearch = TripSearchService();

  Future<List<Trip>> searchTrips({
    required String origin,
    required String date,
    required int departBy,
    required int returnAfter,
    required int returnBy,
    required double minGroundTime,
    required int maxDuration,
    List<String>? destinations,
  }) async {
    try {
      print('🚀 Searching trips directly via Amadeus API (no Flask!)');
      print('📦 Criteria: origin=$origin, date=$date');

      // Create search criteria
      final criteria = SearchCriteria(
        origin: origin,
        date: date,
        departBy: departBy,
        returnAfter: returnAfter,
        returnBy: returnBy,
        minGroundTime: minGroundTime,
        maxDuration: maxDuration,
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
