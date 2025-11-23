import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../models/trip.dart';
import '../services/duffel_service.dart';
import 'trip_detail_screen.dart';

/// Route Viewer Screen - displays weekly flight grid for a specific route
class RouteViewerScreen extends StatefulWidget {
  final String origin;
  final String destination;
  final DateTime weekStart; // Monday of the selected week
  final List<String>? airlineFilters;

  const RouteViewerScreen({
    super.key,
    required this.origin,
    required this.destination,
    required this.weekStart,
    this.airlineFilters,
  });

  @override
  State<RouteViewerScreen> createState() => _RouteViewerScreenState();
}

class _RouteViewerScreenState extends State<RouteViewerScreen> {
  final _duffelService = DuffelService();
  bool _isLoading = true;

  // Data structure: Map<DayIndex, List<FlightInfo>>
  final Map<int, List<FlightInfo>> _outboundFlights = {};
  final Map<int, List<FlightInfo>> _returnFlights = {};

  // Selected flights
  FlightInfo? _selectedOutbound;
  FlightInfo? _selectedReturn;

  @override
  void initState() {
    super.initState();
    _loadWeeklyFlights();
  }

  Future<void> _loadWeeklyFlights() async {
    setState(() => _isLoading = true);

    print('📅 Loading flights for week starting ${DateFormat('MMM d').format(widget.weekStart)}');

    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);

    // Make API calls for each day of the week
    for (int dayIndex = 0; dayIndex < 7; dayIndex++) {
      final date = widget.weekStart.add(Duration(days: dayIndex));
      final dateStr = DateFormat('yyyy-MM-dd').format(date);

      // Skip past dates - Duffel doesn't allow searching for flights in the past
      if (date.isBefore(todayMidnight)) {
        print('  Day ${dayIndex + 1}: ${DateFormat('E MMM d').format(date)} - SKIPPED (past date)');
        continue;
      }

      print('  Day ${dayIndex + 1}: ${DateFormat('E MMM d').format(date)}');

      // Search outbound flights for this day
      final outboundResult = await _duffelService.searchRoundTrip(
        origin: widget.origin,
        destination: widget.destination,
        date: dateStr,
        returnDate: dateStr, // Same day for now (can be adjusted)
        earliestDepartHour: 5,
        departByHour: 23, // Show ALL flight times
        returnAfterHour: 5,
        returnByHour: 23,
        minDurationMinutes: 30,
        maxDurationMinutes: 600,
        allowedCarriers: widget.airlineFilters,
        maxConnections: 0, // nonstop only
      );

      if (outboundResult != null && outboundResult.trips.isNotEmpty) {
        // Extract outbound and return flights
        final outboundFlights = <FlightInfo>[];
        final returnFlights = <FlightInfo>[];

        for (final trip in outboundResult.trips) {
          if (trip.outbound.numStops > 0 || trip.returnFlight.numStops > 0) {
            continue; // enforce nonstop
          }
          // Add outbound flight
          outboundFlights.add(FlightInfo(
            flightNumber: trip.outbound.flightNumbers,
            date: date,
            departTime: trip.outbound.departTime.toIso8601String(),
            arriveTime: trip.outbound.arriveTime.toIso8601String(),
            durationMinutes: trip.outbound.durationMinutes,
            price: trip.outbound.price,
            carrier: trip.outbound.carriers.isNotEmpty ? trip.outbound.carriers.first : '??',
            numStops: trip.outbound.numStops,
          ));

          // Add return flight
          returnFlights.add(FlightInfo(
            flightNumber: trip.returnFlight.flightNumbers,
            date: date,
            departTime: trip.returnFlight.departTime.toIso8601String(),
            arriveTime: trip.returnFlight.arriveTime.toIso8601String(),
            durationMinutes: trip.returnFlight.durationMinutes,
            price: trip.returnFlight.price,
            carrier: trip.returnFlight.carriers.isNotEmpty ? trip.returnFlight.carriers.first : '??',
            numStops: trip.returnFlight.numStops,
          ));
        }

        setState(() {
          _outboundFlights[dayIndex] = outboundFlights;
          _returnFlights[dayIndex] = returnFlights;
        });

        print('    ✅ Found ${outboundFlights.length} outbound, ${returnFlights.length} return flights');
      } else {
        print('    ⚠️ No flights found');
      }

      // Small delay to avoid rate limiting
      await Future.delayed(const Duration(milliseconds: 500));
    }

    setState(() => _isLoading = false);
    print('✅ Weekly flight loading complete');
  }

  @override
  Widget build(BuildContext context) {
    final weekEnd = widget.weekStart.add(const Duration(days: 6));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.origin} ↔ ${widget.destination}'),
            Text(
              '${DateFormat('MMM d').format(widget.weekStart)} - ${DateFormat('MMM d, yyyy').format(weekEnd)}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Selection Instructions
                  if (_selectedOutbound == null || _selectedReturn == null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.blueTint,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: context.infoColor),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Select one outbound and one return flight to view trip details',
                              style: TextStyle(color: context.infoColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Outbound Grid
                  Text(
                    'Outbound: ${widget.origin} → ${widget.destination}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (_selectedOutbound != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Selected: ${_selectedOutbound!.flightNumber} at ${_selectedOutbound!.departTime}',
                        style: TextStyle(color: context.successColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                  const SizedBox(height: 12),
                  _buildFlightGrid(_outboundFlights, isOutbound: true),
                  const SizedBox(height: 32),

                  // Return Grid
                  Text(
                    'Return: ${widget.destination} → ${widget.origin}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (_selectedReturn != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Selected: ${_selectedReturn!.flightNumber} at ${_selectedReturn!.departTime}',
                        style: TextStyle(color: context.successColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                  const SizedBox(height: 12),
                  _buildFlightGrid(_returnFlights, isOutbound: false),
                  const SizedBox(height: 80), // Space for FAB
                ],
              ),
            ),
      floatingActionButton: _selectedOutbound != null && _selectedReturn != null
          ? FloatingActionButton.extended(
              onPressed: _viewTripDetails,
              icon: const Icon(Icons.flight_takeoff),
              label: const Text('View Trip Details'),
              backgroundColor: context.primaryColor,
            )
          : null,
    );
  }

  Widget _buildFlightGrid(Map<int, List<FlightInfo>> flights, {required bool isOutbound}) {
    // Build grid with days as columns, flights as rows
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(context.blueTint),
          columnSpacing: 16,
          columns: [
            const DataColumn(label: Text('Flight')),
            ...List.generate(7, (i) {
              final date = widget.weekStart.add(Duration(days: i));
              return DataColumn(
                label: Text(
                  DateFormat('E\nM/d').format(date),
                  textAlign: TextAlign.center,
                ),
              );
            }),
            const DataColumn(label: Text('Price')),
          ],
          rows: _buildFlightRows(flights, isOutbound: isOutbound),
        ),
      ),
    );
  }

  List<DataRow> _buildFlightRows(Map<int, List<FlightInfo>> flights, {required bool isOutbound}) {
    if (flights.isEmpty) {
      return [
        DataRow(cells: [
          const DataCell(Text('')),
          const DataCell(Text('No flights found')),
          ...List.generate(8, (_) => const DataCell(Text('-'))),
        ]),
      ];
    }

    // Group flights by flight number
    final Map<String, Map<int, FlightInfo>> flightsByNumber = {};

    flights.forEach((dayIndex, dayFlights) {
      for (final flight in dayFlights) {
        if (!flightsByNumber.containsKey(flight.flightNumber)) {
          flightsByNumber[flight.flightNumber] = {};
        }
        flightsByNumber[flight.flightNumber]![dayIndex] = flight;
      }
    });

    // Build rows for each flight number
    final rows = <DataRow>[];
    final sortedFlightNumbers = flightsByNumber.keys.toList()..sort();

    for (final flightNumber in sortedFlightNumbers) {
      final flightDays = flightsByNumber[flightNumber]!;

      // Get a representative flight for pricing (use first available day)
      final firstFlight = flightDays.values.first;
      final rowSelected = isOutbound
          ? flightDays.values.any((f) =>
              _selectedOutbound?.flightNumber == f.flightNumber &&
              _selectedOutbound?.date == f.date)
          : flightDays.values.any((f) =>
              _selectedReturn?.flightNumber == f.flightNumber &&
              _selectedReturn?.date == f.date);

      rows.add(
        DataRow(
          selected: rowSelected,
          color: MaterialStateProperty.resolveWith((states) {
            if (rowSelected) return context.successColor.withOpacity(0.2);
            return null;
          }),
          cells: [
            // Flight number
            DataCell(Text(
              flightNumber,
              style: const TextStyle(fontWeight: FontWeight.bold),
            )),
            // Days of week (show time if flight operates, else -)
            ...List.generate(7, (dayIndex) {
              final flight = flightDays[dayIndex];
              if (flight == null) {
                return const DataCell(Text('-', style: TextStyle(color: Colors.grey)));
              }

              // Extract time from ISO timestamp
              final time = _extractTime(flight.departTime);
              final cellSelected = isOutbound
                  ? (_selectedOutbound?.flightNumber == flight.flightNumber &&
                      _selectedOutbound?.date == flight.date)
                  : (_selectedReturn?.flightNumber == flight.flightNumber &&
                      _selectedReturn?.date == flight.date);
              return DataCell(
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isOutbound) {
                        _selectedOutbound = flight;
                      } else {
                        _selectedReturn = flight;
                      }
                    });
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: cellSelected ? FontWeight.bold : FontWeight.normal,
                          color: cellSelected ? context.successColor : null,
                        ),
                      ),
                      if (flight.numStops > 0)
                        Text(
                          '${flight.numStops}stop',
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              );
            }),
            // Price
            DataCell(Text('\$${firstFlight.price.toStringAsFixed(0)}')),
          ],
        ),
      );
    }

    return rows;
  }

  String _extractTime(String isoTimestamp) {
    try {
      final dt = DateTime.parse(isoTimestamp);
      return DateFormat('HH:mm').format(dt);
    } catch (e) {
      return isoTimestamp; // Return as-is if not ISO format
    }
  }

  String _formatDisplayTime(String isoTimestamp) {
    try {
      final dt = DateTime.parse(isoTimestamp);
      return DateFormat('h:mm a').format(dt);
    } catch (e) {
      return isoTimestamp;
    }
  }

  void _viewTripDetails() {
    if (_selectedOutbound == null || _selectedReturn == null) return;

    // Parse timestamps
    final departOriginTime = DateTime.parse(_selectedOutbound!.departTime);
    final arriveDestTime = DateTime.parse(_selectedOutbound!.arriveTime);
    final departDestTime = DateTime.parse(_selectedReturn!.departTime);
    final arriveOriginTime = DateTime.parse(_selectedReturn!.arriveTime);

    // Calculate ground time (time between landing at destination and departing back)
    final groundTimeDuration = departDestTime.difference(arriveDestTime);
    final groundTimeHours = groundTimeDuration.inSeconds / 3600.0;
    final groundTimeFormatted = _formatDuration(groundTimeDuration.inMinutes);

    // Calculate total trip time (from departure to final arrival)
    final totalTripDuration = arriveOriginTime.difference(departOriginTime);
    final totalTripFormatted = _formatDuration(totalTripDuration.inMinutes);

    // Build Trip object from selected flights
    final trip = Trip(
      origin: widget.origin,
      destination: widget.destination,
      city: widget.destination, // Destination code as city for now
      date: DateFormat('yyyy-MM-dd').format(_selectedOutbound!.date),
      outboundFlight: _selectedOutbound!.flightNumber,
      outboundStops: _selectedOutbound!.numStops,
      departOrigin: _formatDisplayTime(_selectedOutbound!.departTime),
      arriveDestination: _formatDisplayTime(_selectedOutbound!.arriveTime),
      outboundDuration: _formatDuration(_selectedOutbound!.durationMinutes),
      outboundPrice: _selectedOutbound!.price,
      returnFlight: _selectedReturn!.flightNumber,
      returnStops: _selectedReturn!.numStops,
      departDestination: _formatDisplayTime(_selectedReturn!.departTime),
      arriveOrigin: _formatDisplayTime(_selectedReturn!.arriveTime),
      returnDuration: _formatDuration(_selectedReturn!.durationMinutes),
      returnPrice: _selectedReturn!.price,
      groundTimeHours: groundTimeHours,
      groundTime: groundTimeFormatted,
      totalFlightCost: _selectedOutbound!.price + _selectedReturn!.price,
      totalTripTime: totalTripFormatted,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TripDetailScreen(trip: trip),
      ),
    );
  }

  String _formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours}h ${mins.toString().padLeft(2, '0')}m';
  }
}

/// Flight info for grid display
class FlightInfo {
  final String flightNumber;
  final DateTime date; // Date of this flight
  final String departTime;
  final String arriveTime;
  final int durationMinutes;
  final double price;
  final String carrier;
  final int numStops;

  FlightInfo({
    required this.flightNumber,
    required this.date,
    required this.departTime,
    required this.arriveTime,
    required this.durationMinutes,
    required this.price,
    required this.carrier,
    required this.numStops,
  });
}
