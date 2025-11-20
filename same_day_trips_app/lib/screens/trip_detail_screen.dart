import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:intl/intl.dart';
import '../models/trip.dart';
import '../models/stop.dart';
import '../utils/time_formatter.dart';
import '../services/mapbox_service.dart';
import '../services/saved_trips_service.dart';
import 'arrival_assistant_screen.dart';
import 'voice_assistant_screen.dart';
import '../car/car_controller.dart';

class TripDetailScreen extends StatefulWidget {
  final Trip trip;
  final List<Stop>? initialStops;

  const TripDetailScreen({super.key, required this.trip, this.initialStops});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  late List<Stop> _stops;
  final _mapboxService = MapboxService();

  @override
  void initState() {
    super.initState();
    _stops = widget.initialStops != null
        ? List<Stop>.from(widget.initialStops!)
        : [];
    _loadCalendarStops();
  }

  Future<void> _launchUrl(String? url) async {
    if (url == null || url.isEmpty) return;

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _addStop() async {
    final result = await showDialog<Stop>(
      context: context,
      builder: (context) => AddStopDialog(destinationCity: widget.trip.city),
    );

    if (result != null) {
      setState(() {
        _stops.add(result);
      });
      CarController().updateAgenda(widget.trip, _stops);
    }
  }

  Future<void> _loadCalendarStops() async {
    DateTime? tripDate;
    try {
      tripDate = DateTime.parse(widget.trip.date);
    } catch (_) {
      tripDate = DateTime.now();
    }

    setState(() {
      _isLoadingCalendar = true;
      _calendarError = null;
    });

    try {
      final plugin = DeviceCalendarPlugin();
      final permissions = await plugin.requestPermissions();
      if (!permissions.isSuccess || permissions.data != true) {
        setState(() {
          _calendarError = 'Calendar permission denied';
          _isLoadingCalendar = false;
        });
        return;
      }

      final calendarsResult = await plugin.retrieveCalendars();
      if (!calendarsResult.isSuccess || calendarsResult.data == null || calendarsResult.data!.isEmpty) {
        setState(() {
          _calendarError = 'No calendars available';
          _isLoadingCalendar = false;
        });
        return;
      }

      final startOfDay = DateTime(tripDate.year, tripDate.month, tripDate.day);
      final endOfDay = DateTime(tripDate.year, tripDate.month, tripDate.day, 23, 59, 59);

      final newStops = <Stop>[];

      for (final calendar in calendarsResult.data!) {
        final eventsResult = await plugin.retrieveEvents(
          calendar.id,
          RetrieveEventsParams(startDate: startOfDay, endDate: endOfDay),
        );
        if (!eventsResult.isSuccess || eventsResult.data == null) continue;

        for (final event in eventsResult.data!) {
          final start = event.start;
          if (start == null) continue;
          final end = event.end ?? start.add(const Duration(minutes: 60));
          final durationMinutes = end.difference(start).inMinutes.abs();

          final stop = Stop(
            id: 'cal-${event.eventId ?? event.title ?? start.microsecondsSinceEpoch}',
            name: event.title ?? 'Calendar event',
            address: event.location ?? '',
            durationMinutes: durationMinutes > 0 ? durationMinutes : 60,
            latitude: null,
            longitude: null,
            startTime: start,
          );

          final exists = _stops.any((s) => s.id == stop.id);
          if (!exists) {
            newStops.add(stop);
          }
        }
      }

      if (newStops.isNotEmpty) {
        final updated = [..._stops, ...newStops];
        updated.sort((a, b) {
          if (a.startTime != null && b.startTime != null) {
            return a.startTime!.compareTo(b.startTime!);
          }
          if (a.startTime != null) return -1;
          if (b.startTime != null) return 1;
          return 0;
        });
        setState(() {
          _stops = updated;
        });
      }

      setState(() {
        _isLoadingCalendar = false;
      });
    } catch (e) {
      setState(() {
        _calendarError = 'Calendar load failed: $e';
        _isLoadingCalendar = false;
      });
    }
  }

  RouteTimeline? _plannedRoute;
  bool _isPlanningRoute = false;
  String? _routeError;
  bool _isLoadingCalendar = false;
  String? _calendarError;

  Future<MapLocation?> _fetchAirportLocation() async {
    // Try destination airport by IATA code first, fall back to city name
    final queries = [
      '${widget.trip.destination} airport',
      '${widget.trip.city} airport',
    ];

    for (final query in queries) {
      final suggestions = await _mapboxService.searchPlaces(query: query);
      if (suggestions.isEmpty) continue;

      final details = await _mapboxService.retrievePlaceDetails(
        mapboxId: suggestions.first.mapboxId,
        sessionToken: DateTime.now().millisecondsSinceEpoch.toString(),
      );
      if (details != null) {
        return MapLocation(latitude: details.latitude, longitude: details.longitude);
      }
    }
    return null;
  }

  Future<void> _planDayRoute() async {
    if (_stops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one stop to plan the day')),
      );
      return;
    }

    final stopsWithCoords = _stops.where((s) => s.latitude != null && s.longitude != null).toList();
    if (stopsWithCoords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stops need locations before planning the route')),
      );
      return;
    }

    setState(() {
      _isPlanningRoute = true;
      _routeError = null;
    });

    try {
      final airportLoc = await _fetchAirportLocation();
      if (airportLoc == null) {
        setState(() {
          _routeError = 'Could not find airport location for routing';
          _isPlanningRoute = false;
        });
        return;
      }

      final stops = stopsWithCoords
          .map((s) => StopWithLocation(
                name: s.name,
                durationMinutes: s.durationMinutes,
                location: MapLocation(latitude: s.latitude!, longitude: s.longitude!),
                startTime: s.startTime,
              ))
          .toList();

      final route = await _mapboxService.planOptimalRoute(
        airport: airportLoc,
        stops: stops,
      );

      setState(() {
        _plannedRoute = route;
        _isPlanningRoute = false;
        _routeError = route == null ? 'Unable to plan route right now' : null;
      });
    } catch (e) {
      setState(() {
        _routeError = 'Route planning failed: $e';
        _isPlanningRoute = false;
      });
    }
  }

  Future<void> _saveTrip() async {
    // Show dialog to optionally add notes
    final notesController = TextEditingController();
    final notes = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Trip'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Save this trip to your agendas?',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'e.g., Client meeting in Houston',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, notesController.text),
            icon: const Icon(Icons.bookmark),
            label: const Text('Save'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (notes != null) {
      // Save the trip with stops
      final savedTripsService = SavedTripsService();
      final success = await savedTripsService.saveTrip(
        widget.trip,
        notes: notes.isEmpty ? null : notes,
        stops: _stops,  // Include the stops!
      );

      if (!mounted) return;

      // Show confirmation
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Trip saved to your agendas!'
                : 'Failed to save trip. Please try again.',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.trip.destination} Day Trip'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saveTrip,
        icon: const Icon(Icons.bookmark),
        label: const Text('Save Trip'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Destination Header
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            widget.trip.destination,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.trip.city,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(
                                widget.trip.date,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Colors.grey.shade600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _InfoChip(
                          icon: Icons.schedule,
                          label: 'Meeting Time',
                          value: widget.trip.groundTime,
                          color: Colors.green,
                        ),
                        _InfoChip(
                          icon: Icons.attach_money,
                          label: 'Flight Cost',
                          value: '\$${widget.trip.totalFlightCost.toStringAsFixed(0)}',
                          color: Colors.blue,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // AI Assistant Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ArrivalAssistantScreen(
                            trip: widget.trip,
                            stops: _stops,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.chat),
                    label: const Text('Text Chat'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => VoiceAssistantScreen(
                            trip: widget.trip,
                            stops: _stops,
                          ),
                        ),
                      );
                      setState(() {});
                      CarController().updateAgenda(widget.trip, _stops);
                    },
                    icon: const Icon(Icons.mic),
                    label: const Text('Voice Mode'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Itinerary
            Text(
              'Your Itinerary',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),

            // Outbound Flight
            _FlightCard(
              title: 'Outbound Flight',
              icon: Icons.flight_takeoff,
              flightNumber: widget.trip.outboundFlight,
              departure: TimeFormatter.formatWithTimezone(widget.trip.departOrigin, widget.trip.origin),
              arrival: TimeFormatter.formatWithTimezone(widget.trip.arriveDestination, widget.trip.destination),
              duration: widget.trip.outboundDuration,
              stops: widget.trip.outboundStops,
            ),
            const SizedBox(height: 16),

            // Ground Time
            Card(
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.location_city, color: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Time in City',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            widget.trip.groundTime,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: Colors.green.shade700,
                                ),
                          ),
                          Text(
                            '${widget.trip.groundTimeHours.toStringAsFixed(1)} hours for meetings',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Stops Planning Section
            Text(
              'Plan Your Stops',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_stops.isEmpty)
                      Column(
                        children: [
                          Icon(Icons.location_on_outlined, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text(
                            'No stops added yet',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add meetings or appointments during your trip',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      )
                    else
                      ..._stops.asMap().entries.map((entry) {
                        final index = entry.key;
                        final stop = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stop.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (stop.startTime != null)
                            Text(
                              'Starts ${DateFormat('h:mm a').format(stop.startTime!)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade700,
                            ),
                          ),
                          if (stop.startTime != null)
                            Text(
                              'Starts ${DateFormat('h:mm a').format(stop.startTime!)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          Text(
                            stop.address,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                                      ),
                                    ),
                                    Text(
                                      '${stop.formatDuration()} planned',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () {
                                  setState(() {
                            _stops.removeAt(index);
                          });
                        },
                        color: Colors.red,
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _addStop,
              icon: const Icon(Icons.add_location),
              label: Text(_stops.isEmpty ? 'Add Stop' : 'Add Another Stop'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            if (_isLoadingCalendar)
              Row(
                children: const [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Syncing calendar events...'),
                ],
              ),
            if (_calendarError != null && !_isLoadingCalendar)
              Text(
                _calendarError!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            if (!_isLoadingCalendar && _calendarError == null)
              Text(
                'Calendar events for this date are included automatically.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isPlanningRoute ? null : _planDayRoute,
              icon: _isPlanningRoute
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.route),
                      label: Text(_isPlanningRoute ? 'Planning...' : 'Plan the Day'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    if (_routeError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _routeError!,
                        style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                      ),
                    ],
                    if (_plannedRoute != null) ...[
                      const SizedBox(height: 12),
                      Card(
                        color: Colors.green.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.directions, color: Colors.green),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Optimized Route',
                                    style: TextStyle(
                                      color: Colors.green.shade800,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${_plannedRoute!.formatDuration(_plannedRoute!.totalDrivingMinutes * 60)} driving',
                                    style: TextStyle(color: Colors.green.shade800),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ..._plannedRoute!.stops.asMap().entries.map((entry) {
                                final legIndex = entry.key;
                                final stop = entry.value;
                                final legSeconds = _plannedRoute!.legDurations[legIndex];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Text('${legIndex + 1}. ${stop.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                      const Spacer(),
                                      Text(_plannedRoute!.formatDuration(legSeconds)),
                                    ],
                                  ),
                                );
                              }),
                              // Final leg back to airport
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    const Text('Back to airport', style: TextStyle(fontWeight: FontWeight.w600)),
                                    const Spacer(),
                                    Text(_plannedRoute!.formatDuration(_plannedRoute!.legDurations.last)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Return Flight
            _FlightCard(
              title: 'Return Flight',
              icon: Icons.flight_land,
              flightNumber: widget.trip.returnFlight,
              departure: TimeFormatter.formatWithTimezone(widget.trip.departDestination, widget.trip.destination),
              arrival: TimeFormatter.formatWithTimezone(widget.trip.arriveOrigin, widget.trip.origin),
              duration: widget.trip.returnDuration,
              stops: widget.trip.returnStops,
            ),
            const SizedBox(height: 24),

            // Total Summary
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Trip Time:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(widget.trip.totalTripTime),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Flight Cost:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          '\$${widget.trip.totalFlightCost.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Booking Links
            if (widget.trip.googleFlightsUrl != null || widget.trip.kayakUrl != null || widget.trip.airlineUrl != null) ...[
              Text(
                'Book Your Flights',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (widget.trip.googleFlightsUrl != null)
                _BookingButton(
                  label: 'Search on Google Flights',
                  icon: Icons.search,
                  color: Colors.blue,
                  onPressed: () => _launchUrl(widget.trip.googleFlightsUrl),
                ),
              if (widget.trip.kayakUrl != null)
                _BookingButton(
                  label: 'Compare on Kayak',
                  icon: Icons.compare_arrows,
                  color: Colors.orange,
                  onPressed: () => _launchUrl(widget.trip.kayakUrl),
                ),
              if (widget.trip.airlineUrl != null)
                _BookingButton(
                  label: 'Search AA Award Flights',
                  icon: Icons.card_giftcard,
                  color: Colors.red,
                  onPressed: () => _launchUrl(widget.trip.airlineUrl),
                ),
              const SizedBox(height: 24),
            ],

            // Ground Transportation
            if (widget.trip.turoSearchUrl != null) ...[
              Text(
                'Ground Transportation',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.directions_car, size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Rent a Car',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                if (widget.trip.turoVehicle != null)
                                  Text(
                                    widget.trip.turoVehicle!,
                                    style: TextStyle(color: Colors.grey.shade600),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => _launchUrl(widget.trip.turoSearchUrl),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Browse Cars on Turo'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Tips
            Card(
              color: Colors.amber.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline, color: Colors.amber.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Travel Tips',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('• Arrive at airport 60-90 minutes before departure'),
                    const Text('• Download airline app for mobile boarding passes'),
                    const Text('• Consider TSA PreCheck to save time'),
                    const Text('• Pack light - personal item only saves time'),
                    const Text('• Schedule meetings near the airport to maximize time'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _FlightCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String flightNumber;
  final String departure;
  final String arrival;
  final String duration;
  final int stops;

  const _FlightCard({
    required this.title,
    required this.icon,
    required this.flightNumber,
    required this.departure,
    required this.arrival,
    required this.duration,
    required this.stops,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              flightNumber,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Depart', style: TextStyle(fontSize: 12)),
                      Text(
                        departure,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward, color: Colors.grey.shade400),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Arrive', style: TextStyle(fontSize: 12)),
                      Text(
                        arrival,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  duration,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(width: 16),
                Icon(
                  stops == 0 ? Icons.check_circle : Icons.swap_horiz,
                  size: 16,
                  color: stops == 0 ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 4),
                Text(
                  stops == 0 ? 'Nonstop' : '$stops stop${stops > 1 ? 's' : ''}',
                  style: TextStyle(
                    color: stops == 0 ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _BookingButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.all(16),
          ),
        ),
      ),
    );
  }
}

class AddStopDialog extends StatefulWidget {
  final String destinationCity;

  const AddStopDialog({super.key, required this.destinationCity});

  @override
  State<AddStopDialog> createState() => _AddStopDialogState();
}

class _AddStopDialogState extends State<AddStopDialog> {
  final _mapboxService = MapboxService();
  final _searchController = TextEditingController();

  int _durationMinutes = 30;
  PlaceDetails? _selectedPlace;
  List<SearchSuggestion> _suggestions = [];
  bool _isSearching = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchPlaces(String query) async {
    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final results = await _mapboxService.searchPlaces(query: query);
      setState(() {
        _suggestions = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _errorMessage = 'Search failed: $e';
      });
    }
  }

  Future<void> _selectSuggestion(SearchSuggestion suggestion) async {
    try {
      final details = await _mapboxService.retrievePlaceDetails(
        mapboxId: suggestion.mapboxId,
        sessionToken: DateTime.now().millisecondsSinceEpoch.toString(),
      );

      if (details != null) {
        setState(() {
          _selectedPlace = details;
          _searchController.text = details.name;
          _suggestions = [];
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load place details: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Stop'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Search field
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search for location',
                  hintText: 'e.g., Texas Children\'s Hospital',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _isSearching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  // Debounce search
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (_searchController.text == value) {
                      _searchPlaces(value);
                    }
                  });
                },
              ),

              // Error message
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),

              // Suggestions list
              if (_suggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    itemBuilder: (context, index) {
                      final suggestion = _suggestions[index];
                      return ListTile(
                        leading: const Icon(Icons.location_on, size: 20),
                        title: Text(suggestion.name),
                        subtitle: Text(
                          suggestion.displayText,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onTap: () => _selectSuggestion(suggestion),
                      );
                    },
                  ),
                ),

              // Selected place display
              if (_selectedPlace != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedPlace!.name,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _selectedPlace!.fullAddress,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Duration selector
              Row(
                children: [
                  const Icon(Icons.schedule, color: Colors.grey),
                  const SizedBox(width: 8),
                  const Text('Duration:'),
                  const Spacer(),
                  DropdownButton<int>(
                    value: _durationMinutes,
                    items: [15, 30, 45, 60, 90, 120, 180, 240].map((minutes) {
                      String label;
                      if (minutes < 60) {
                        label = '$minutes min';
                      } else {
                        final hours = minutes ~/ 60;
                        final mins = minutes % 60;
                        label = mins == 0 ? '${hours}h' : '${hours}h ${mins}m';
                      }
                      return DropdownMenuItem(
                        value: minutes,
                        child: Text(label),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _durationMinutes = value!;
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedPlace == null
              ? null
              : () {
                  final stop = Stop(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: _selectedPlace!.name,
                    address: _selectedPlace!.fullAddress,
                    durationMinutes: _durationMinutes,
                    latitude: _selectedPlace!.latitude,
                    longitude: _selectedPlace!.longitude,
                  );
                  Navigator.pop(context, stop);
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          child: const Text('Add Stop'),
        ),
      ],
    );
  }
}
