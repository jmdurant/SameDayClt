/// Represents a flight offer from Amadeus API
class FlightOffer {
  final DateTime departTime;
  final DateTime arriveTime;
  final int durationMinutes;
  final String flightNumbers;
  final int numStops;
  final double price;

  // Store local hours directly from API to avoid timezone conversion issues
  final int departHourLocal;
  final int arriveHourLocal;

  FlightOffer({
    required this.departTime,
    required this.arriveTime,
    required this.durationMinutes,
    required this.flightNumbers,
    required this.numStops,
    required this.price,
    required this.departHourLocal,
    required this.arriveHourLocal,
  });

  factory FlightOffer.fromJson(Map<String, dynamic> json) {
    final itinerary = json['itineraries'][0] as Map<String, dynamic>;
    final segments = itinerary['segments'] as List;
    final firstSegment = segments.first as Map<String, dynamic>;
    final lastSegment = segments.last as Map<String, dynamic>;

    // Parse departure time
    // Amadeus returns times in ISO format with timezone (e.g., "2025-11-15T07:35:00+01:00")
    // Extract local hour BEFORE parsing to avoid timezone conversion issues
    final departTimeStr = firstSegment['departure']['at'] as String;
    final departTime = DateTime.parse(departTimeStr);
    final departHourLocal = int.parse(departTimeStr.substring(11, 13)); // Extract "HH" from "YYYY-MM-DDTHH:MM:SS"

    // Parse arrival time
    final arriveTimeStr = lastSegment['arrival']['at'] as String;
    final arriveTime = DateTime.parse(arriveTimeStr);
    final arriveHourLocal = int.parse(arriveTimeStr.substring(11, 13));

    // Parse duration (format: "PT2H15M")
    final durationStr = itinerary['duration'] as String;
    final durationMinutes = _parseDuration(durationStr);

    // Get flight numbers
    final flightNumbers = segments
        .map((seg) => '${seg['carrierCode']}${seg['number']}')
        .join(', ');

    // Number of stops
    final numStops = segments.length - 1;

    // Price
    final price = double.parse(json['price']['total'] as String);

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
  }

  static int _parseDuration(String duration) {
    // Parse ISO 8601 duration format: "PT2H15M" -> 135 minutes
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

  String formatTime() {
    return '${departTime.hour.toString().padLeft(2, '0')}:${departTime.minute.toString().padLeft(2, '0')}';
  }

  String formatDuration() {
    final hours = durationMinutes ~/ 60;
    final mins = durationMinutes % 60;
    return '${hours}h ${mins.toString().padLeft(2, '0')}m';
  }
}

/// Represents a destination discovered via Flight Inspiration Search
class Destination {
  final String code;
  final String city;

  Destination({
    required this.code,
    required this.city,
  });

  factory Destination.fromJson(Map<String, dynamic> json) {
    final code = json['destination'] as String;
    return Destination(
      code: code,
      city: code, // Flight Inspiration doesn't provide city names
    );
  }
}

/// Search criteria for finding same-day trips
class SearchCriteria {
  final String origin;
  final String date;
  final int departBy; // Hour in 24hr format (e.g., 9 = 9:00 AM)
  final int returnAfter; // Hour in 24hr format (e.g., 15 = 3:00 PM)
  final int returnBy; // Hour in 24hr format (e.g., 19 = 7:00 PM)
  final double minGroundTime; // Minimum hours on the ground
  final int maxDuration; // Maximum flight duration in minutes
  final List<String>? destinations; // Optional specific destinations

  SearchCriteria({
    required this.origin,
    required this.date,
    required this.departBy,
    required this.returnAfter,
    required this.returnBy,
    required this.minGroundTime,
    required this.maxDuration,
    this.destinations,
  });
}
