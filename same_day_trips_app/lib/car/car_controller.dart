import 'dart:io' show Platform;
import 'package:flutter_carplay/flutter_carplay.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/trip_agenda.dart';
import '../models/trip.dart'; // Needed for the mock
import '../models/stop.dart';

class CarController {
  static final CarController _instance = CarController._internal();
  FlutterAndroidAuto? _androidAuto;

  factory CarController() {
    return _instance;
  }

  CarController._internal();

  void initialize() {
    // Android Auto: set up basic root list template
    if (Platform.isAndroid) {
      _androidAuto ??= FlutterAndroidAuto();
      _setAndroidMenu();
      return;
    }

    // CarPlay (iOS)
    try {

    FlutterCarplay.setRootTemplate(
      rootTemplate: CPListTemplate(
        sections: [
          CPListSection(
            items: [
              CPListItem(
                text: "Same-Day Trips",
                detailText: "Find trips from your location",
                onPress: (complete, item) {
                  // TODO: Navigate to search or show trips
                  complete();
                },
                image: 'assets/images/logo.png', // Ensure this asset exists or remove
              ),
              CPListItem(
                text: "Saved Trips",
                detailText: "View your planned itineraries",
                onPress: (complete, item) {
                  complete();
                },
              ),
              CPListItem(
                text: "Demo Agenda: NYC Day Trip",
                detailText: "Tap to view itinerary",
                onPress: (complete, item) {
                  _showDemoAgenda();
                  complete();
                },
              ),
            ],
            header: "Menu",
          ),
        ],
        title: "Same-Day Trips",
        systemIcon: "house.fill",
      ),
      animated: true,
    );
    } catch (e) {
      // Silently skip on platforms without CarPlay
      print('CarPlay not available: $e');
    }
  }

  void _showDemoAgenda() {
    // Mock data to demonstrate the model usage
    final mockTrip = Trip(
      origin: "CLT",
      destination: "JFK",
      city: "New York",
      date: "2025-11-20",
      outboundFlight: "AA123",
      outboundStops: 0,
      departOrigin: "06:00",
      arriveDestination: "09:00",
      outboundDuration: "2h",
      outboundPrice: 150,
      returnFlight: "AA456",
      returnStops: 0,
      departDestination: "20:00",
      arriveOrigin: "22:00",
      returnDuration: "2h",
      returnPrice: 150,
      groundTimeHours: 11,
      groundTime: "11h",
      totalFlightCost: 300,
      totalTripTime: "16h",
    );

    final agenda = TripAgenda(
      trip: mockTrip,
      items: [
        AgendaItem(
          time: "06:00 AM",
          title: "Depart CLT",
          description: "Flight AA123 to JFK",
          locationQuery: "Charlotte Douglas International Airport",
          type: AgendaItemType.flight,
        ),
        AgendaItem(
          time: "09:00 AM",
          title: "Arrive JFK",
          description: "Terminal 8",
          locationQuery: "JFK Airport Terminal 8",
          type: AgendaItemType.flight,
        ),
        AgendaItem(
          time: "10:00 AM",
          title: "Breakfast",
          description: "Sarabeth's Central Park South",
          locationQuery: "Sarabeth's Central Park South",
          type: AgendaItemType.meal,
        ),
        AgendaItem(
          time: "01:00 PM",
          title: "Museum Tour",
          description: "The Metropolitan Museum of Art",
          locationQuery: "The Metropolitan Museum of Art",
          type: AgendaItemType.activity,
        ),
        AgendaItem(
          time: "08:00 PM",
          title: "Depart JFK",
          description: "Flight AA456 to CLT",
          locationQuery: "JFK Airport",
          type: AgendaItemType.flight,
        ),
      ],
    );

    _pushAgendaTemplate(agenda);
  }

  void updateAgenda(Trip trip, List<Stop> stops) {
    // Build agenda items (shared between CarPlay and Android Auto)
    final items = <AgendaItem>[];

    // 1. Outbound Flight (Departure)
    items.add(AgendaItem(
      time: trip.departOrigin,
      title: "Depart ${trip.origin}",
      description: "Flight ${trip.outboundFlight}",
      locationQuery: "${trip.origin} Airport",
      type: AgendaItemType.flight,
    ));

    // 2. Outbound Flight (Arrival)
    items.add(AgendaItem(
      time: trip.arriveDestination,
      title: "Arrive ${trip.destination}",
      description: "Ground time: ${trip.groundTime}",
      locationQuery: "${trip.destination} Airport",
      type: AgendaItemType.flight,
    ));

    // 3. User Added Stops
    for (var stop in stops) {
      items.add(AgendaItem(
        time: "Planned", // We don't have exact times for stops yet, just duration
        title: stop.name,
        description: "${stop.durationMinutes} min • ${stop.address}",
        locationQuery: "${stop.name}, ${stop.address}",
        type: AgendaItemType.activity,
      ));
    }

    // 4. Return Flight
    items.add(AgendaItem(
      time: trip.departDestination,
      title: "Depart ${trip.destination}",
      description: "Flight ${trip.returnFlight}",
      locationQuery: "${trip.destination} Airport",
      type: AgendaItemType.flight,
    ));

    final agenda = TripAgenda(trip: trip, items: items);
    _pushAgendaTemplate(agenda);
  }

  void _pushAgendaTemplate(TripAgenda agenda) {
    if (Platform.isAndroid) {
      _setAndroidAgenda(agenda);
      return;
    }

    // Convert AgendaItems to CPListItems
    final listItems = agenda.items.map((item) {
      return CPListItem(
        text: "${item.time} - ${item.title}",
        detailText: item.description,
        image: item.iconAsset ?? "assets/images/logo.png", // Fallback icon
        onPress: (complete, self) {
          _launchMaps(item.locationQuery);
          complete();
        },
      );
    }).toList();

    FlutterCarplay.push(
      template: CPListTemplate(
        sections: [
          CPListSection(
            header: "Itinerary for ${agenda.trip.city}",
            items: listItems,
          ),
        ],
        title: "${agenda.trip.city} Agenda",
        systemIcon: "calendar",
      ),
      animated: true,
    );
  }

  void _setAndroidMenu() {
    final menuTemplate = AAListTemplate(
      title: "Same-Day Trips",
      sections: [
        AAListSection(
          title: "Menu",
          items: [
            AAListItem(
              title: "Same-Day Trips",
              subtitle: "Find trips from your location",
              onPress: (complete, self) {
                complete();
              },
            ),
            AAListItem(
              title: "Saved Trips",
              subtitle: "View your planned itineraries",
              onPress: (complete, self) {
                complete();
              },
            ),
            AAListItem(
              title: "Demo Agenda: NYC Day Trip",
              subtitle: "Tap to view itinerary",
              onPress: (complete, self) {
                _showDemoAgenda();
                complete();
              },
            ),
          ],
        ),
      ],
    );

    FlutterAndroidAuto.setRootTemplate(template: menuTemplate);
  }

  void _setAndroidAgenda(TripAgenda agenda) {
    final section = AAListSection(
      title: "Itinerary for ${agenda.trip.city}",
      items: agenda.items
          .map((item) => AAListItem(
                title: "${item.time} - ${item.title}",
                subtitle: item.description,
                onPress: (complete, self) {
                  _launchMaps(item.locationQuery);
                  complete();
                },
              ))
          .toList(),
    );

    final template = AAListTemplate(
      title: "${agenda.trip.city} Agenda",
      sections: [section],
    );

    FlutterAndroidAuto.setRootTemplate(template: template);
  }

  Future<void> _launchMaps(String query) async {
    final Uri uri = Uri.parse("geo:0,0?q=${Uri.encodeComponent(query)}");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      print("Could not launch maps for $query");
    }
  }
}
