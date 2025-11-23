import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../models/trip.dart';
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

    // TODO: Implement API calls for each day of the week
    // For now, just simulate loading
    await Future.delayed(const Duration(seconds: 2));

    setState(() => _isLoading = false);
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
            const DataColumn(label: Text('Select')),
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

    // TODO: Group flights by flight number and build rows
    // For now, return placeholder
    return [];
  }

  void _viewTripDetails() {
    if (_selectedOutbound == null || _selectedReturn == null) return;

    // Build Trip object from selected flights
    final trip = Trip(
      origin: widget.origin,
      destination: widget.destination,
      city: widget.destination, // TODO: Get actual city name
      date: DateFormat('yyyy-MM-dd').format(_selectedOutbound!.date),
      outboundFlight: _selectedOutbound!.flightNumber,
      outboundStops: _selectedOutbound!.numStops,
      departOrigin: _selectedOutbound!.departTime,
      arriveDestination: _selectedOutbound!.arriveTime,
      outboundDuration: _formatDuration(_selectedOutbound!.durationMinutes),
      outboundPrice: _selectedOutbound!.price,
      returnFlight: _selectedReturn!.flightNumber,
      returnStops: _selectedReturn!.numStops,
      departDestination: _selectedReturn!.departTime,
      arriveOrigin: _selectedReturn!.arriveTime,
      returnDuration: _formatDuration(_selectedReturn!.durationMinutes),
      returnPrice: _selectedReturn!.price,
      groundTimeHours: 0.0, // TODO: Calculate from dates
      groundTime: '0h', // TODO: Calculate
      totalFlightCost: _selectedOutbound!.price + _selectedReturn!.price,
      totalTripTime: '0h', // TODO: Calculate
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
