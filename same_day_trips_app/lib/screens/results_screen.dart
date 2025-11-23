import 'dart:async';
import 'package:flutter/material.dart';
import '../models/trip.dart';
import '../utils/time_formatter.dart';
import '../theme/app_colors.dart';
import 'trip_detail_screen.dart';

class ResultsScreen extends StatefulWidget {
  final List<Trip>? trips; // Optional for legacy support
  final Stream<Trip>? tripStream; // For progressive results
  final Map<String, dynamic> searchParams;

  const ResultsScreen({
    super.key,
    this.trips,
    this.tripStream,
    required this.searchParams,
  }) : assert(trips != null || tripStream != null, 'Either trips or tripStream must be provided');

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  String _sortBy = 'groundTime'; // groundTime, cost, totalTime, homeDeparture, destDeparture, city
  bool _sortAscending = false; // Default to descending for groundTime (max time first)

  List<Trip> _trips = [];
  bool _isLoading = false;
  StreamSubscription<Trip>? _streamSubscription;

  @override
  void initState() {
    super.initState();

    if (widget.trips != null) {
      // Legacy mode: use provided list
      _trips = widget.trips!;
    } else if (widget.tripStream != null) {
      // Progressive mode: listen to stream
      _isLoading = true;
      _streamSubscription = widget.tripStream!.listen(
        (trip) {
          setState(() {
            _trips.add(trip);
          });
        },
        onDone: () {
          setState(() {
            _isLoading = false;
          });
          print('✅ All trips received: ${_trips.length} total');
        },
        onError: (error) {
          setState(() {
            _isLoading = false;
          });
          print('❌ Stream error: $error');
        },
      );
    }
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    super.dispose();
  }

  List<Trip> get _sortedTrips {
    final trips = List<Trip>.from(_trips);

    trips.sort((a, b) {
      int comparison;
      switch (_sortBy) {
        case 'cost':
          comparison = a.totalFlightCost.compareTo(b.totalFlightCost);
          break;
        case 'totalTime':
          comparison = a.totalTripTime.compareTo(b.totalTripTime);
          break;
        case 'homeDeparture':
          comparison = a.departOrigin.compareTo(b.departOrigin);
          break;
        case 'destDeparture':
          comparison = a.departDestination.compareTo(b.departDestination);
          break;
        case 'city':
          comparison = a.city.compareTo(b.city);
          break;
        case 'groundTime':
        default:
          comparison = a.groundTimeHours.compareTo(b.groundTimeHours);
          break;
      }
      return _sortAscending ? comparison : -comparison;
    });

    return trips;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Trips'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            onSelected: (value) {
              setState(() {
                if (_sortBy == value) {
                  _sortAscending = !_sortAscending;
                } else {
                  _sortBy = value;
                  // Set default direction based on sort type
                  // Cost, times, and city should be ascending (low to high / early to late / A-Z)
                  // Ground time should be descending (high to low)
                  _sortAscending = (value == 'cost' ||
                                   value == 'homeDeparture' ||
                                   value == 'destDeparture' ||
                                   value == 'totalTime' ||
                                   value == 'city');
                }
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'groundTime',
                child: Text('Ground Time (High to Low)'),
              ),
              const PopupMenuItem(
                value: 'cost',
                child: Text('Price (Low to High)'),
              ),
              const PopupMenuItem(
                value: 'city',
                child: Text('City/State (A-Z)'),
              ),
              const PopupMenuItem(
                value: 'homeDeparture',
                child: Text('Home Departure Time'),
              ),
              const PopupMenuItem(
                value: 'destDeparture',
                child: Text('Destination Departure Time'),
              ),
              const PopupMenuItem(
                value: 'totalTime',
                child: Text('Total Trip Time'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Summary
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: context.blueTint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isLoading
                            ? 'Found ${_trips.length} trips (searching...)'
                            : 'Found ${_trips.length} viable trips',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (_isLoading)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'From ${widget.searchParams['origin']} on ${widget.searchParams['date']}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  'Depart by ${widget.searchParams['departBy']}:00 • Back by ${widget.searchParams['returnBy']}:00',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),

          // Results List
          Expanded(
            child: _trips.isEmpty && !_isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 64, color: context.textSecondary),
                        const SizedBox(height: 16),
                        Text(
                          'No trips found',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try adjusting your search criteria',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: context.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _sortedTrips.length,
                    itemBuilder: (context, index) {
                      final trip = _sortedTrips[index];
                      return TripCard(
                        trip: trip,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => TripDetailScreen(trip: trip),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class TripCard extends StatelessWidget {
  final Trip trip;
  final VoidCallback onTap;

  const TripCard({
    super.key,
    required this.trip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Destination Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: context.primaryColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      trip.destination,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      trip.city,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '\$${trip.totalFlightCost.toStringAsFixed(0)}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: context.successColor,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Ground Time - Most Important Info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.greenTint,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.successColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule, color: context.successColor),
                    const SizedBox(width: 8),
                    Text(
                      'Meeting Time: ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: context.successColor,
                      ),
                    ),
                    Text(
                      trip.groundTime,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: context.successColor,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '(${trip.groundTimeHours.toStringAsFixed(1)} hrs)',
                      style: TextStyle(color: context.successColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Outbound Flight
              Row(
                children: [
                  const Icon(Icons.flight_takeoff, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Outbound: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: Text(
                      '${TimeFormatter.formatWithTimezone(trip.departOrigin, trip.origin)} → ${TimeFormatter.formatWithTimezone(trip.arriveDestination, trip.destination)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  '${trip.outboundFlight} • ${trip.outboundDuration} • ${trip.outboundStops == 0 ? 'Nonstop' : '${trip.outboundStops} stop${trip.outboundStops > 1 ? 's' : ''}'}',
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
              ),
              const SizedBox(height: 8),

              // Return Flight
              Row(
                children: [
                  const Icon(Icons.flight_land, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Return: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: Text(
                      '${TimeFormatter.formatWithTimezone(trip.departDestination, trip.destination)} → ${TimeFormatter.formatWithTimezone(trip.arriveOrigin, trip.origin)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  '${trip.returnFlight} • ${trip.returnDuration} • ${trip.returnStops == 0 ? 'Nonstop' : '${trip.returnStops} stop${trip.returnStops > 1 ? 's' : ''}'}',
                  style: TextStyle(fontSize: 12, color: context.textSecondary),
                ),
              ),
              const SizedBox(height: 12),

              // Total Trip Time
              Row(
                children: [
                  Icon(Icons.access_time, size: 16, color: context.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Total trip time: ${trip.totalTripTime}',
                    style: TextStyle(fontSize: 12, color: context.textSecondary),
                  ),
                  const Spacer(),
                  const Icon(Icons.arrow_forward_ios, size: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
