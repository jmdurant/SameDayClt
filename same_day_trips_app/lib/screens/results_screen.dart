import 'package:flutter/material.dart';
import '../models/trip.dart';
import 'trip_detail_screen.dart';

class ResultsScreen extends StatefulWidget {
  final List<Trip> trips;
  final Map<String, dynamic> searchParams;

  const ResultsScreen({
    super.key,
    required this.trips,
    required this.searchParams,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  String _sortBy = 'groundTime'; // groundTime, cost, totalTime
  bool _sortAscending = false;

  List<Trip> get _sortedTrips {
    final trips = List<Trip>.from(widget.trips);

    trips.sort((a, b) {
      int comparison;
      switch (_sortBy) {
        case 'cost':
          comparison = a.totalFlightCost.compareTo(b.totalFlightCost);
          break;
        case 'totalTime':
          comparison = a.totalTripTime.compareTo(b.totalTripTime);
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
                  _sortAscending = false;
                }
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'groundTime', child: Text('Sort by Meeting Time')),
              const PopupMenuItem(value: 'cost', child: Text('Sort by Cost')),
              const PopupMenuItem(value: 'totalTime', child: Text('Sort by Total Time')),
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
            color: Colors.blue.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Found ${widget.trips.length} viable trips',
                  style: Theme.of(context).textTheme.titleLarge,
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
            child: widget.trips.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'No trips found',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try adjusting your search criteria',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey.shade600,
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
                      color: Colors.blue,
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
                          color: Colors.green.shade700,
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
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'Meeting Time: ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade900,
                      ),
                    ),
                    Text(
                      trip.groundTime,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '(${trip.groundTimeHours.toStringAsFixed(1)} hrs)',
                      style: TextStyle(color: Colors.green.shade700),
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
                      '${trip.departOrigin} → ${trip.arriveDestination}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '\$${trip.outboundPrice.toStringAsFixed(0)}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  '${trip.outboundFlight} • ${trip.outboundDuration} • ${trip.outboundStops == 0 ? 'Nonstop' : '${trip.outboundStops} stop${trip.outboundStops > 1 ? 's' : ''}'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
                      '${trip.departDestination} → ${trip.arriveOrigin}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '\$${trip.returnPrice.toStringAsFixed(0)}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  '${trip.returnFlight} • ${trip.returnDuration} • ${trip.returnStops == 0 ? 'Nonstop' : '${trip.returnStops} stop${trip.returnStops > 1 ? 's' : ''}'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(height: 12),

              // Total Trip Time
              Row(
                children: [
                  Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    'Total trip time: ${trip.totalTripTime}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
