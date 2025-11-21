import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../models/trip.dart';
import '../models/stop.dart';
import '../utils/time_formatter.dart';
import '../services/mapbox_service.dart';
import '../services/saved_trips_service.dart';
import 'arrival_assistant_screen.dart';
import 'voice_assistant_screen.dart';
import '../car/car_controller.dart';
import '../theme/app_colors.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

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

  String? _extractCarrierCode(String flightNumbers) {
    final first = flightNumbers.split(',').first.trim();
    final match = RegExp(r'([A-Z]{2})\\d').firstMatch(first);
    return match != null ? match.group(1) : null;
  }

  String? _buildAirlineBookingUrl() {
    final code = _extractCarrierCode(widget.trip.outboundFlight);
    if (code == null) return null;

    final origin = widget.trip.origin;
    final dest = widget.trip.destination;
    final date = widget.trip.date; // expected yyyy-MM-dd

    switch (code) {
      case 'AA':
        return 'https://www.aa.com/flights/$origin-$dest/$date/$date/1/0/0/ECONOMY/true';
      case 'DL':
        return 'https://www.delta.com/flight-search/book-a-flight?tripType=ROUND_TRIP&departureDate=$date&returnDate=$date&originCode=$origin&destinationCode=$dest&paxCount=1';
      case 'UA':
        return 'https://www.united.com/en/us/fsr/choose-flights?f=$origin&t=$dest&d=$date&r=$date&px=1&taxng=1&idx=1';
      case 'WN':
        return 'https://www.southwest.com/air/booking/select.html?originationAirportCode=$origin&destinationAirportCode=$dest&departureDate=$date&returnDate=$date&adultPassengersCount=1';
      case 'B6':
        return 'https://jetblue.com/booking/flights?from=$origin&to=$dest&depart=$date&return=$date&isMultiCity=false&noOfRoute=1&lang=en&adults=1';
      case 'AS':
        return 'https://www.alaskaair.com/planbook/shopping?trip=roundtrip&awardBooking=false&adultCount=1&from=$origin&to=$dest&departureDate=$date&returnDate=$date';
      case 'NK':
        return 'https://www.spirit.com/book/flights?journey=roundTrip&origin=$origin&destination=$dest&departDate=$date&returnDate=$date&ADT=1';
      case 'F9':
        return 'https://booking.flyfrontier.com/Flight/Search?trip=roundtrip&from=$origin&to=$dest&departDate=$date&returnDate=$date&adults=1';
      default:
        return null;
    }
  }

  String _airlineNameForCode(String code) {
    const names = {
      'AA': 'American',
      'DL': 'Delta',
      'UA': 'United',
      'WN': 'Southwest',
      'B6': 'JetBlue',
      'AS': 'Alaska',
      'NK': 'Spirit',
      'F9': 'Frontier',
    };
    return names[code] ?? code;
  }

  void _openAirlineWebView(String url, {String? title}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AirlineCheckoutScreen(
          url: url,
          title: title ?? 'Airline Checkout',
        ),
      ),
    );
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
  AgendaTimeline? _agenda;
  bool _isPlanningRoute = false;
  String? _routeError;
  bool _isLoadingCalendar = false;
  String? _calendarError;

  Future<void> _printAgenda() async {
    if (_agenda == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please plan the day first before printing')),
      );
      return;
    }

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => _generateAgendaPdf(format),
    );
  }

  Future<void> _shareAgenda() async {
    if (_agenda == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please plan the day first before sharing')),
      );
      return;
    }

    // Generate text format of the agenda
    final buffer = StringBuffer();

    // Header
    buffer.writeln('🗓️ SAME-DAY TRIP TO ${widget.trip.city.toUpperCase()}');
    buffer.writeln('📍 ${widget.trip.destination} • ${widget.trip.date}');
    buffer.writeln('');

    // Outbound Flight
    buffer.writeln('✈️ OUTBOUND FLIGHT');
    buffer.writeln('${widget.trip.outboundFlight}');
    buffer.writeln('Depart: ${widget.trip.departOrigin}');
    buffer.writeln('Arrive: ${widget.trip.arriveDestination}');
    buffer.writeln('Duration: ${widget.trip.outboundDuration} • ${widget.trip.outboundStops == 0 ? 'Nonstop' : '${widget.trip.outboundStops} stop(s)'}');
    buffer.writeln('Cost: \$${widget.trip.outboundPrice.toStringAsFixed(2)}');
    buffer.writeln('');

    // Day Plan
    buffer.writeln('📋 DAY PLAN');
    buffer.writeln('${DateFormat('h:mm a').format(_agenda!.arrivalTime)} - Arrive in ${widget.trip.city}');
    buffer.writeln('${DateFormat('h:mm a').format(_agenda!.startTime)} - Exit airport (+${_agenda!.airportExitMinutes} min)');
    buffer.writeln('');

    // Agenda items
    for (final item in _agenda!.items) {
      final time = DateFormat('h:mm a').format(item.time);
      if (item.type == AgendaItemType.travel) {
        final distance = item.distanceMiles != null ? ' • ${item.distanceMiles!.toStringAsFixed(1)} mi' : '';
        buffer.writeln('$time - 🚗 ${item.description} (${item.durationMinutes} min$distance)');
      } else if (item.type == AgendaItemType.stop) {
        buffer.writeln('$time - 📍 ${item.description} (${item.durationMinutes} min)');
      }
    }

    buffer.writeln('');
    buffer.writeln('${DateFormat('h:mm a').format(_agenda!.endTime)} - Must be at airport (-${_agenda!.airportBufferMinutes} min)');
    buffer.writeln('${DateFormat('h:mm a').format(_agenda!.departureTime)} - Depart ${widget.trip.city}');
    buffer.writeln('');

    // Driving Summary
    if (_plannedRoute != null) {
      buffer.writeln('🚗 TOTAL DRIVING: ${_plannedRoute!.totalDrivingMiles.toStringAsFixed(1)} miles');
      buffer.writeln('');
    }

    // Return Flight
    buffer.writeln('✈️ RETURN FLIGHT');
    buffer.writeln('${widget.trip.returnFlight}');
    buffer.writeln('Depart: ${widget.trip.departDestination}');
    buffer.writeln('Arrive: ${widget.trip.arriveOrigin}');
    buffer.writeln('Duration: ${widget.trip.returnDuration} • ${widget.trip.returnStops == 0 ? 'Nonstop' : '${widget.trip.returnStops} stop(s)'}');
    buffer.writeln('Cost: \$${widget.trip.returnPrice.toStringAsFixed(2)}');
    buffer.writeln('');

    // Cost Summary
    buffer.writeln('💰 TOTAL EXPENSES');
    buffer.writeln('Flights: \$${widget.trip.totalFlightCost.toStringAsFixed(2)}');
    if (_plannedRoute != null) {
      final mileageCost = _plannedRoute!.totalDrivingMiles * 0.70;
      buffer.writeln('Mileage (${_plannedRoute!.totalDrivingMiles.toStringAsFixed(1)} mi @ \$0.70/mi): \$${mileageCost.toStringAsFixed(2)}');
      buffer.writeln('TOTAL: \$${(widget.trip.totalFlightCost + mileageCost).toStringAsFixed(2)}');
    } else {
      buffer.writeln('TOTAL: \$${widget.trip.totalFlightCost.toStringAsFixed(2)}');
    }
    buffer.writeln('');

    // Status
    buffer.writeln(_agenda!.isFeasible ? '✅ ${_agenda!.remainingTimeMessage}' : '⚠️ ${_agenda!.remainingTimeMessage}');

    // Share the text
    await Share.share(
      buffer.toString(),
      subject: 'Same-Day Trip to ${widget.trip.city}',
    );
  }

  Future<Uint8List> _generateAgendaPdf(PdfPageFormat format) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue900,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Same-Day Trip Expense Report',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      '${widget.trip.city} (${widget.trip.destination})',
                      style: pw.TextStyle(
                        fontSize: 18,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.Text(
                      'Date: ${widget.trip.date}',
                      style: const pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Outbound Flight
              _buildFlightSection(
                'Outbound Flight',
                widget.trip.outboundFlight,
                widget.trip.departOrigin,
                widget.trip.arriveDestination,
                widget.trip.outboundDuration,
                widget.trip.outboundStops,
                widget.trip.outboundPrice,
              ),
              pw.SizedBox(height: 16),

              // Agenda Timeline
              pw.Text(
                'Day Plan & Itinerary',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                padding: const pw.EdgeInsets.all(12),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Arrival
                    _buildAgendaRow(
                      DateFormat('h:mm a').format(_agenda!.arrivalTime),
                      'Arrive in ${widget.trip.city}',
                      null,
                      null,
                      true,
                    ),
                    _buildAgendaRow(
                      DateFormat('h:mm a').format(_agenda!.startTime),
                      'Exit airport (+${_agenda!.airportExitMinutes} min)',
                      null,
                      null,
                      false,
                    ),
                    pw.Divider(),

                    // Agenda items
                    ..._agenda!.items.map((item) => _buildAgendaRow(
                      DateFormat('h:mm a').format(item.time),
                      item.description,
                      item.durationMinutes,
                      item.distanceMiles,
                      item.type == AgendaItemType.stop,
                    )),
                    pw.Divider(),

                    // Return to airport
                    _buildAgendaRow(
                      DateFormat('h:mm a').format(_agenda!.endTime),
                      'Must be at airport (-${_agenda!.airportBufferMinutes} min)',
                      null,
                      null,
                      false,
                    ),
                    _buildAgendaRow(
                      DateFormat('h:mm a').format(_agenda!.departureTime),
                      'Depart ${widget.trip.city}',
                      null,
                      null,
                      true,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Total driving miles summary
              if (_plannedRoute != null)
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue50,
                    border: pw.Border.all(color: PdfColors.blue200),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Total Driving Distance:',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        '${_plannedRoute!.totalDrivingMiles.toStringAsFixed(1)} miles',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              pw.SizedBox(height: 16),

              // Return Flight
              _buildFlightSection(
                'Return Flight',
                widget.trip.returnFlight,
                widget.trip.departDestination,
                widget.trip.arriveOrigin,
                widget.trip.returnDuration,
                widget.trip.returnStops,
                widget.trip.returnPrice,
              ),
              pw.SizedBox(height: 20),

              // Cost Summary
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey200,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Outbound Flight:'),
                        pw.Text('\$${widget.trip.outboundPrice.toStringAsFixed(2)}'),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Return Flight:'),
                        pw.Text('\$${widget.trip.returnPrice.toStringAsFixed(2)}'),
                      ],
                    ),
                    if (_plannedRoute != null) ...[
                      pw.SizedBox(height: 4),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Mileage (${_plannedRoute!.totalDrivingMiles.toStringAsFixed(1)} mi @ \$0.70/mi):'),
                          pw.Text('\$${(_plannedRoute!.totalDrivingMiles * 0.70).toStringAsFixed(2)}'),
                        ],
                      ),
                    ],
                    pw.Divider(),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Total Expense:',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        pw.Text(
                          _plannedRoute != null
                              ? '\$${(widget.trip.totalFlightCost + (_plannedRoute!.totalDrivingMiles * 0.70)).toStringAsFixed(2)}'
                              : '\$${widget.trip.totalFlightCost.toStringAsFixed(2)}',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Footer
              pw.Text(
                'Generated on ${DateFormat('MMMM d, y \'at\' h:mm a').format(DateTime.now())}',
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildFlightSection(
    String title,
    String flightNumber,
    String departure,
    String arrival,
    String duration,
    int stops,
    double price,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                '\$${price.toStringAsFixed(2)}',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(flightNumber),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Depart', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text(
                    departure,
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.Text('→', style: const pw.TextStyle(fontSize: 20)),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Arrive', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text(
                    arrival,
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '$duration • ${stops == 0 ? 'Nonstop' : '$stops stop${stops > 1 ? 's' : ''}'}',
            style: const pw.TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildAgendaRow(
    String time,
    String description,
    int? durationMinutes,
    double? distanceMiles,
    bool isBold,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 70,
            child: pw.Text(
              time,
              style: pw.TextStyle(
                fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  description,
                  style: pw.TextStyle(
                    fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
                  ),
                ),
                if (durationMinutes != null && durationMinutes > 0)
                  pw.Text(
                    distanceMiles != null
                        ? '$durationMinutes min drive • ${distanceMiles.toStringAsFixed(1)} mi'
                        : '($durationMinutes min)',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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

      // Generate agenda timeline with actual times
      AgendaTimeline? agenda;
      if (route != null &&
          widget.trip.arriveDestinationIso != null &&
          widget.trip.departDestinationIso != null) {
        agenda = route.generateAgenda(
          arrivalTimeIso: widget.trip.arriveDestinationIso!,
          departureTimeIso: widget.trip.departDestinationIso!,
        );
      }

      setState(() {
        _plannedRoute = route;
        _agenda = agenda;
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
              style: TextStyle(color: context.textSecondary),
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
              backgroundColor: context.primaryColor,
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
          backgroundColor: success ? context.successColor : context.errorColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final smartAirlineUrl = _buildAirlineBookingUrl();
    final smartAirlineCode = _extractCarrierCode(widget.trip.outboundFlight);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.trip.destination} Day Trip'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saveTrip,
        icon: const Icon(Icons.bookmark),
        label: const Text('Save Trip'),
        backgroundColor: context.primaryColor,
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
                            color: context.primaryColor,
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
                                      color: context.textSecondary,
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
                          color: context.successColor,
                        ),
                        _InfoChip(
                          icon: Icons.attach_money,
                          label: 'Flight Cost',
                          value: '\$${widget.trip.totalFlightCost.toStringAsFixed(0)}',
                          color: context.primaryColor,
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
                      backgroundColor: const Color(0xFF9C27B0),
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
                      backgroundColor: const Color(0xFF673AB7),
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
              departure: TimeFormatter.formatWithTimezone(widget.trip.departOrigin, widget.trip.origin, tzOffset: widget.trip.departOriginTz),
              arrival: TimeFormatter.formatWithTimezone(widget.trip.arriveDestination, widget.trip.destination, tzOffset: widget.trip.arriveDestinationTz),
              duration: widget.trip.outboundDuration,
              stops: widget.trip.outboundStops,
            ),
            const SizedBox(height: 16),

            // Ground Time
            Card(
              color: context.greenTint,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.successColor,
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
                                  color: context.successColor,
                                ),
                          ),
                          Text(
                            '${widget.trip.groundTimeHours.toStringAsFixed(1)} hours for meetings',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.textSecondary,
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
                          Icon(Icons.location_on_outlined, size: 48, color: context.borderColor),
                          const SizedBox(height: 8),
                          Text(
                            'No stops added yet',
                            style: TextStyle(color: context.textSecondary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add meetings or appointments during your trip',
                            style: TextStyle(fontSize: 12, color: context.textSecondary),
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
                                  color: context.primaryColor,
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
                                color: context.primaryColor,
                              ),
                            ),
                          Text(
                            stop.address,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.textSecondary,
                            ),
                          ),
                          Text(
                            '${stop.formatDuration()} planned',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.primaryColor,
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
                                color: context.errorColor,
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
                backgroundColor: context.primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            if (_isLoadingCalendar)
              const Row(
                children: [
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
                style: TextStyle(color: context.errorColor, fontSize: 12),
              ),
            if (!_isLoadingCalendar && _calendarError == null)
              Text(
                'Calendar events for this date are included automatically.',
                style: TextStyle(color: context.textSecondary, fontSize: 12),
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
                backgroundColor: context.successColor,
                foregroundColor: Colors.white,
              ),
            ),
            if (_routeError != null) ...[
              const SizedBox(height: 8),
              Text(
                _routeError!,
                style: TextStyle(color: context.errorColor, fontSize: 12),
              ),
            ],
                    if (_agenda != null) ...[
                      const SizedBox(height: 12),
                      Card(
                        color: _agenda!.isFeasible ? context.greenTint : context.orangeTint,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _agenda!.isFeasible ? Icons.event_available : Icons.warning,
                                    color: _agenda!.isFeasible ? context.successColor : context.warningColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Your Day Plan',
                                      style: TextStyle(
                                        color: _agenda!.isFeasible ? context.successColor : context.warningColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _shareAgenda,
                                    icon: const Icon(Icons.share),
                                    tooltip: 'Share Agenda',
                                    color: context.primaryColor,
                                  ),
                                  IconButton(
                                    onPressed: _printAgenda,
                                    icon: const Icon(Icons.print),
                                    tooltip: 'Print Expense Report',
                                    color: context.primaryColor,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Arrival at destination
                              _AgendaRow(
                                time: DateFormat('h:mm a').format(_agenda!.arrivalTime),
                                description: 'Arrive in ${widget.trip.city}',
                                isArrival: true,
                              ),
                              _AgendaRow(
                                time: DateFormat('h:mm a').format(_agenda!.startTime),
                                description: 'Exit airport (+${_agenda!.airportExitMinutes} min)',
                                isDeparture: true,
                              ),
                              const Divider(height: 16),
                              // Agenda items (travel & stops)
                              ..._agenda!.items.asMap().entries.map((entry) {
                                final item = entry.value;
                                return _AgendaRow(
                                  time: DateFormat('h:mm a').format(item.time),
                                  description: item.description,
                                  isTravel: item.type == AgendaItemType.travel,
                                  isStop: item.type == AgendaItemType.stop,
                                  durationMinutes: item.durationMinutes,
                                  distanceMiles: item.distanceMiles,
                                );
                              }),
                              const Divider(height: 16),
                              // Return to airport requirement
                              _AgendaRow(
                                time: DateFormat('h:mm a').format(_agenda!.endTime),
                                description: 'Must be at airport (-${_agenda!.airportBufferMinutes} min)',
                                isDeparture: true,
                              ),
                              _AgendaRow(
                                time: DateFormat('h:mm a').format(_agenda!.departureTime),
                                description: 'Depart ${widget.trip.city}',
                                isArrival: true,
                              ),
                              const SizedBox(height: 12),
                              // Remaining time message
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _agenda!.isFeasible ? context.successColor.withOpacity(0.1) : context.errorColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _agenda!.isFeasible ? context.successColor : context.errorColor,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _agenda!.isFeasible ? Icons.check_circle : Icons.error,
                                      color: _agenda!.isFeasible ? context.successColor : context.errorColor,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _agenda!.remainingTimeMessage,
                                        style: TextStyle(
                                          color: _agenda!.isFeasible ? context.successColor : context.errorColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else if (_plannedRoute != null) ...[
                      const SizedBox(height: 12),
                      Card(
                        color: context.greenTint,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.directions, color: context.successColor),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Optimized Route',
                                    style: TextStyle(
                                      color: context.successColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${_plannedRoute!.formatDuration(_plannedRoute!.totalDrivingMinutes * 60)} driving',
                                    style: TextStyle(color: context.successColor),
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
              departure: TimeFormatter.formatWithTimezone(widget.trip.departDestination, widget.trip.destination, tzOffset: widget.trip.departDestinationTz),
              arrival: TimeFormatter.formatWithTimezone(widget.trip.arriveOrigin, widget.trip.origin, tzOffset: widget.trip.arriveOriginTz),
              duration: widget.trip.returnDuration,
              stops: widget.trip.returnStops,
            ),
            const SizedBox(height: 24),

            // Total Summary
            Card(
              color: context.blueTint,
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
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: context.successColor,
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
            if (smartAirlineUrl != null ||
                widget.trip.googleFlightsUrl != null ||
                widget.trip.kayakUrl != null ||
                (smartAirlineCode == 'AA' && widget.trip.airlineUrl != null)) ...[
              Text(
                'Book Your Flights',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (smartAirlineUrl != null)
                _BookingButton(
                  label: 'Book on ${_airlineNameForCode(smartAirlineCode ?? '')}',
                  icon: Icons.flight_takeoff,
                  color: context.successColor,
                  onPressed: () => _openAirlineWebView(smartAirlineUrl, title: 'Book ${widget.trip.outboundFlight}'),
                ),
              if (widget.trip.googleFlightsUrl != null)
                _BookingButton(
                  label: 'Search on Google Flights',
                  icon: Icons.search,
                  color: context.primaryColor,
                  onPressed: () => _launchUrl(widget.trip.googleFlightsUrl),
                ),
              if (widget.trip.kayakUrl != null)
                _BookingButton(
                  label: 'Compare on Kayak',
                  icon: Icons.compare_arrows,
                  color: context.warningColor,
                  onPressed: () => _launchUrl(widget.trip.kayakUrl),
                ),
              if (widget.trip.airlineUrl != null && smartAirlineCode == 'AA')
                _BookingButton(
                  label: 'Search AA Award Flights',
                  icon: Icons.card_giftcard,
                  color: context.errorColor,
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
                                    style: TextStyle(color: context.textSecondary),
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
                          backgroundColor: const Color(0xFF9C27B0),
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
              color: context.orangeTint,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline, color: context.warningColor),
                        const SizedBox(width: 8),
                        Text(
                          'Travel Tips',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: context.warningColor,
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
          style: TextStyle(fontSize: 12, color: context.textSecondary),
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
                Icon(icon, color: context.primaryColor),
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
                color: context.textSecondary,
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
                Icon(Icons.arrow_forward, color: context.borderColor),
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
                Icon(Icons.access_time, size: 16, color: context.textSecondary),
                const SizedBox(width: 4),
                Text(
                  duration,
                  style: TextStyle(color: context.textSecondary),
                ),
                const SizedBox(width: 16),
                Icon(
                  stops == 0 ? Icons.check_circle : Icons.swap_horiz,
                  size: 16,
                  color: stops == 0 ? context.successColor : context.warningColor,
                ),
                const SizedBox(width: 4),
                Text(
                  stops == 0 ? 'Nonstop' : '$stops stop${stops > 1 ? 's' : ''}',
                  style: TextStyle(
                    color: stops == 0 ? context.successColor : context.warningColor,
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
  final VoidCallback? onPressed;

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

class AirlineCheckoutScreen extends StatelessWidget {
  final String url;
  final String title;

  const AirlineCheckoutScreen({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(url),
        ),
      ),
    );
  }
}

class _AgendaRow extends StatelessWidget {
  final String time;
  final String description;
  final bool isArrival;
  final bool isDeparture;
  final bool isTravel;
  final bool isStop;
  final int? durationMinutes;
  final double? distanceMiles;

  const _AgendaRow({
    required this.time,
    required this.description,
    this.isArrival = false,
    this.isDeparture = false,
    this.isTravel = false,
    this.isStop = false,
    this.durationMinutes,
    this.distanceMiles,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color iconColor;

    if (isArrival) {
      icon = Icons.flight_land;
      iconColor = context.primaryColor;
    } else if (isDeparture) {
      icon = Icons.airport_shuttle;
      iconColor = context.primaryColor;
    } else if (isTravel) {
      icon = Icons.directions_car;
      iconColor = context.textSecondary;
    } else if (isStop) {
      icon = Icons.place;
      iconColor = context.successColor;
    } else {
      icon = Icons.circle;
      iconColor = context.borderColor;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              time,
              style: TextStyle(
                fontWeight: isArrival || isDeparture || isStop ? FontWeight.bold : FontWeight.normal,
                color: isArrival || isDeparture || isStop ? context.primaryColor : context.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: TextStyle(
                    fontWeight: isArrival || isDeparture || isStop ? FontWeight.w600 : FontWeight.normal,
                    color: isTravel ? context.textSecondary : null,
                  ),
                ),
                if (durationMinutes != null && durationMinutes! > 0)
                  Text(
                    isStop
                        ? '($durationMinutes min)'
                        : distanceMiles != null
                            ? '${durationMinutes} min drive • ${distanceMiles!.toStringAsFixed(1)} mi'
                            : '${durationMinutes} min drive',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ],
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
                    style: TextStyle(color: context.errorColor, fontSize: 12),
                  ),
                ),

              // Suggestions list
              if (_suggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    border: Border.all(color: context.borderColor),
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
                    color: context.successTint,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.successColor),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: context.successColor),
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
            backgroundColor: context.primaryColor,
            foregroundColor: Colors.white,
          ),
          child: const Text('Add Stop'),
        ),
      ],
    );
  }
}
