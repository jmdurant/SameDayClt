import 'dart:convert';
import 'trip.dart';
import 'stop.dart';

/// Represents a saved trip/agenda
class SavedTrip {
  final String id;
  final Trip trip;
  final DateTime savedAt;
  final String? notes;
  final List<Stop> stops;

  SavedTrip({
    required this.id,
    required this.trip,
    required this.savedAt,
    this.notes,
    this.stops = const [],
  });

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'trip': trip.toJson(),
      'savedAt': savedAt.toIso8601String(),
      'notes': notes,
      'stops': stops.map((stop) => stop.toJson()).toList(),
    };
  }

  /// Create from JSON
  factory SavedTrip.fromJson(Map<String, dynamic> json) {
    final stopsJson = json['stops'] as List<dynamic>?;
    final stops = stopsJson != null
        ? stopsJson.map((s) => Stop.fromJson(s as Map<String, dynamic>)).toList()
        : <Stop>[];

    return SavedTrip(
      id: json['id'] as String,
      trip: Trip.fromJson(json['trip'] as Map<String, dynamic>),
      savedAt: DateTime.parse(json['savedAt'] as String),
      notes: json['notes'] as String?,
      stops: stops,
    );
  }

  /// Create a copy with updated values
  SavedTrip copyWith({
    String? id,
    Trip? trip,
    DateTime? savedAt,
    String? notes,
    List<Stop>? stops,
  }) {
    return SavedTrip(
      id: id ?? this.id,
      trip: trip ?? this.trip,
      savedAt: savedAt ?? this.savedAt,
      notes: notes ?? this.notes,
      stops: stops ?? this.stops,
    );
  }
}
