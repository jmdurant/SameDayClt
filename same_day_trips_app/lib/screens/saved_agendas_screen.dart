import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/saved_trip.dart';
import '../services/saved_trips_service.dart';
import 'trip_detail_screen.dart';
import '../theme/app_colors.dart';

class SavedAgendasScreen extends StatefulWidget {
  const SavedAgendasScreen({super.key});

  @override
  State<SavedAgendasScreen> createState() => _SavedAgendasScreenState();
}

class _SavedAgendasScreenState extends State<SavedAgendasScreen> {
  final _savedTripsService = SavedTripsService();
  List<SavedTrip> _savedTrips = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedTrips();
  }

  Future<void> _loadSavedTrips() async {
    setState(() => _isLoading = true);
    try {
      final trips = await _savedTripsService.getSavedTrips();
      setState(() {
        _savedTrips = trips;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading saved trips: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteTrip(SavedTrip savedTrip) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Trip'),
        content: Text(
          'Are you sure you want to delete this trip to ${savedTrip.trip.city}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.errorColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _savedTripsService.deleteTrip(savedTrip.id);

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Trip deleted'),
            backgroundColor: context.successColor,
          ),
        );
        _loadSavedTrips(); // Reload the list
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to delete trip'),
            backgroundColor: context.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Agendas'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _savedTrips.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bookmark_border,
                        size: 64,
                        color: context.borderColor,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No saved trips yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: context.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Save trips from the trip details page',
                        style: TextStyle(
                          fontSize: 14,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _savedTrips.length,
                  itemBuilder: (context, index) {
                    final savedTrip = _savedTrips[index];
                    return _SavedTripCard(
                      savedTrip: savedTrip,
                      onTap: () async {
                        // Navigate to trip details with saved stops
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TripDetailScreen(
                              trip: savedTrip.trip,
                              initialStops: savedTrip.stops,
                            ),
                          ),
                        );
                      },
                      onDelete: () => _deleteTrip(savedTrip),
                    );
                  },
                ),
    );
  }
}

class _SavedTripCard extends StatelessWidget {
  final SavedTrip savedTrip;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SavedTripCard({
    required this.savedTrip,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final trip = savedTrip.trip;
    final savedDate = DateFormat('MMM d, yyyy').format(savedTrip.savedAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with destination and delete button
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: context.primaryColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      trip.destination,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.city,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          trip.date,
                          style: TextStyle(
                            fontSize: 14,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    color: context.errorColor,
                    onPressed: onDelete,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Trip summary
              Row(
                children: [
                  _InfoItem(
                    icon: Icons.schedule,
                    label: trip.groundTime,
                    color: context.successColor,
                  ),
                  const SizedBox(width: 16),
                  _InfoItem(
                    icon: Icons.attach_money,
                    label: '\$${trip.totalFlightCost.toStringAsFixed(0)}',
                    color: context.primaryColor,
                  ),
                  const SizedBox(width: 16),
                  _InfoItem(
                    icon: Icons.flight_takeoff,
                    label: '${trip.departOrigin} - ${trip.arriveOrigin}',
                    color: context.warningColor,
                  ),
                ],
              ),

              // Notes if present
              if (savedTrip.notes != null && savedTrip.notes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.blueTint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.note,
                        size: 16,
                        color: context.primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          savedTrip.notes!,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.primaryColor,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Saved date
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.bookmark,
                    size: 14,
                    color: context.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Saved $savedDate',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: context.textSecondary,
          ),
        ),
      ],
    );
  }
}
