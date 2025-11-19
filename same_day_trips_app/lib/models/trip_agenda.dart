import 'trip.dart';

enum AgendaItemType {
  flight,
  activity,
  meal,
  transport,
}

class AgendaItem {
  final String time;
  final String title;
  final String description;
  final String locationQuery; // For navigation
  final AgendaItemType type;
  final String? iconAsset; // Optional override

  AgendaItem({
    required this.time,
    required this.title,
    required this.description,
    required this.locationQuery,
    required this.type,
    this.iconAsset,
  });
}

class TripAgenda {
  final Trip trip;
  final List<AgendaItem> items;

  TripAgenda({
    required this.trip,
    required this.items,
  });

  /// Create an agenda from a Trip (auto-populates flights)
  factory TripAgenda.fromTrip(Trip trip) {
    final items = <AgendaItem>[];

    // 1. Outbound Flight
    items.add(AgendaItem(
      time: trip.departOrigin,
      title: "Depart ${trip.origin}",
      description: "Flight ${trip.outboundFlight}",
      locationQuery: "${trip.origin} Airport",
      type: AgendaItemType.flight,
      iconAsset: "assets/images/plane.png",
    ));

    items.add(AgendaItem(
      time: trip.arriveDestination,
      title: "Arrive ${trip.destination}",
      description: "Ground time: ${trip.groundTime}",
      locationQuery: "${trip.destination} Airport",
      type: AgendaItemType.flight,
      iconAsset: "assets/images/plane.png",
    ));

    // 2. Placeholder for activities (to be filled by AI or user)
    items.add(AgendaItem(
      time: _addHours(trip.arriveDestination, 1),
      title: "Explore ${trip.city}",
      description: "Free time in the city",
      locationQuery: "${trip.city} City Center",
      type: AgendaItemType.activity,
    ));

    // 3. Return Flight
    items.add(AgendaItem(
      time: trip.departDestination,
      title: "Depart ${trip.destination}",
      description: "Flight ${trip.returnFlight}",
      locationQuery: "${trip.destination} Airport",
      type: AgendaItemType.flight,
      iconAsset: "assets/images/plane.png",
    ));

    return TripAgenda(trip: trip, items: items);
  }

  static String _addHours(String timeStr, int hours) {
    // Basic helper to add hours to "HH:mm" string
    try {
      final parts = timeStr.split(':');
      final h = int.parse(parts[0]);
      final m = parts[1];
      return "${(h + hours) % 24}:$m";
    } catch (e) {
      return timeStr;
    }
  }
}
