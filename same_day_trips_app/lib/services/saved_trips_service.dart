import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/saved_trip.dart';
import '../models/trip.dart';
import '../models/stop.dart';

/// Service for managing saved trips/agendas
class SavedTripsService {
  static const String _key = 'saved_trips';

  /// Get all saved trips
  Future<List<SavedTrip>> getSavedTrips() async {
    final prefs = await SharedPreferences.getInstance();
    final String? tripsJson = prefs.getString(_key);

    if (tripsJson == null || tripsJson.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> tripsList = jsonDecode(tripsJson);
      return tripsList
          .map((json) => SavedTrip.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error loading saved trips: $e');
      return [];
    }
  }

  /// Save a new trip
  Future<bool> saveTrip(Trip trip, {String? notes, List<Stop>? stops}) async {
    try {
      final savedTrips = await getSavedTrips();

      final newSavedTrip = SavedTrip(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        trip: trip,
        savedAt: DateTime.now(),
        notes: notes,
        stops: stops ?? [],
      );

      savedTrips.add(newSavedTrip);

      final prefs = await SharedPreferences.getInstance();
      final tripsJson = jsonEncode(savedTrips.map((t) => t.toJson()).toList());
      await prefs.setString(_key, tripsJson);

      print('✅ Trip saved successfully');
      return true;
    } catch (e) {
      print('❌ Error saving trip: $e');
      return false;
    }
  }

  /// Delete a saved trip
  Future<bool> deleteTrip(String id) async {
    try {
      final savedTrips = await getSavedTrips();
      savedTrips.removeWhere((trip) => trip.id == id);

      final prefs = await SharedPreferences.getInstance();
      final tripsJson = jsonEncode(savedTrips.map((t) => t.toJson()).toList());
      await prefs.setString(_key, tripsJson);

      print('✅ Trip deleted successfully');
      return true;
    } catch (e) {
      print('❌ Error deleting trip: $e');
      return false;
    }
  }

  /// Update notes for a saved trip
  Future<bool> updateNotes(String id, String notes) async {
    try {
      final savedTrips = await getSavedTrips();
      final index = savedTrips.indexWhere((trip) => trip.id == id);

      if (index == -1) {
        return false;
      }

      savedTrips[index] = savedTrips[index].copyWith(notes: notes);

      final prefs = await SharedPreferences.getInstance();
      final tripsJson = jsonEncode(savedTrips.map((t) => t.toJson()).toList());
      await prefs.setString(_key, tripsJson);

      print('✅ Notes updated successfully');
      return true;
    } catch (e) {
      print('❌ Error updating notes: $e');
      return false;
    }
  }

  /// Clear all saved trips
  Future<bool> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
      print('✅ All saved trips cleared');
      return true;
    } catch (e) {
      print('❌ Error clearing saved trips: $e');
      return false;
    }
  }
}
