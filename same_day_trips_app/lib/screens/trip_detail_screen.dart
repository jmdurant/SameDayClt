import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/trip.dart';

class TripDetailScreen extends StatelessWidget {
  final Trip trip;

  const TripDetailScreen({super.key, required this.trip});

  Future<void> _launchUrl(String? url) async {
    if (url == null || url.isEmpty) return;

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${trip.destination} Day Trip'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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
                            trip.destination,
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
                                trip.city,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(
                                trip.date,
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
                          value: trip.groundTime,
                          color: Colors.green,
                        ),
                        _InfoChip(
                          icon: Icons.attach_money,
                          label: 'Flight Cost',
                          value: '\$${trip.totalFlightCost.toStringAsFixed(0)}',
                          color: Colors.blue,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

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
              flightNumber: trip.outboundFlight,
              departure: trip.departOrigin,
              arrival: trip.arriveDestination,
              duration: trip.outboundDuration,
              stops: trip.outboundStops,
              price: trip.outboundPrice,
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
                            trip.groundTime,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: Colors.green.shade700,
                                ),
                          ),
                          Text(
                            '${trip.groundTimeHours.toStringAsFixed(1)} hours for meetings',
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

            // Return Flight
            _FlightCard(
              title: 'Return Flight',
              icon: Icons.flight_land,
              flightNumber: trip.returnFlight,
              departure: trip.departDestination,
              arrival: trip.arriveOrigin,
              duration: trip.returnDuration,
              stops: trip.returnStops,
              price: trip.returnPrice,
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
                        Text(trip.totalTripTime),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Flight Cost:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          '\$${trip.totalFlightCost.toStringAsFixed(2)}',
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
            if (trip.googleFlightsUrl != null || trip.kayakUrl != null || trip.airlineUrl != null) ...[
              Text(
                'Book Your Flights',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (trip.googleFlightsUrl != null)
                _BookingButton(
                  label: 'Search on Google Flights',
                  icon: Icons.search,
                  color: Colors.blue,
                  onPressed: () => _launchUrl(trip.googleFlightsUrl),
                ),
              if (trip.kayakUrl != null)
                _BookingButton(
                  label: 'Compare on Kayak',
                  icon: Icons.compare_arrows,
                  color: Colors.orange,
                  onPressed: () => _launchUrl(trip.kayakUrl),
                ),
              if (trip.airlineUrl != null)
                _BookingButton(
                  label: 'Search AA Award Flights',
                  icon: Icons.card_giftcard,
                  color: Colors.red,
                  onPressed: () => _launchUrl(trip.airlineUrl),
                ),
              const SizedBox(height: 24),
            ],

            // Ground Transportation
            if (trip.turoSearchUrl != null) ...[
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
                                if (trip.turoVehicle != null)
                                  Text(
                                    trip.turoVehicle!,
                                    style: TextStyle(color: Colors.grey.shade600),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => _launchUrl(trip.turoSearchUrl),
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
  final double price;

  const _FlightCard({
    required this.title,
    required this.icon,
    required this.flightNumber,
    required this.departure,
    required this.arrival,
    required this.duration,
    required this.stops,
    required this.price,
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
                Text(
                  '\$${price.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
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
