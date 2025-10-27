import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/trip.dart';
import '../models/stop.dart';
import 'voice_assistant_screen.dart';

class AndroidAutoHomeScreen extends StatefulWidget {
  const AndroidAutoHomeScreen({super.key});

  @override
  State<AndroidAutoHomeScreen> createState() => _AndroidAutoHomeScreenState();
}

class _AndroidAutoHomeScreenState extends State<AndroidAutoHomeScreen> {
  Trip? _activeTrip;
  List<Stop> _stops = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadActiveTrip();
  }

  Future<void> _loadActiveTrip() async {
    // TODO: Load today's active trip from local storage or API
    // For now, create a mock trip for Android Auto testing
    setState(() {
      _activeTrip = Trip(
        city: 'Atlanta',
        origin: 'CLT',
        destination: 'ATL',
        date: DateTime.now().toString().split(' ')[0],
        outboundFlight: 'AA 1234',
        outboundStops: 0,
        departOrigin: '8:00 AM',
        arriveDestination: '9:30 AM',
        outboundDuration: '1h 30m',
        outboundPrice: 150.0,
        returnFlight: 'AA 5678',
        returnStops: 0,
        departDestination: '4:00 PM',
        arriveOrigin: '5:30 PM',
        returnDuration: '1h 30m',
        returnPrice: 150.0,
        groundTimeHours: 6.5,
        groundTime: '6h 30m',
        totalFlightCost: 300.0,
        totalTripTime: '8h 30m',
      );
      _isLoading = false;
    });

    // Android Auto: Launch voice assistant immediately (no delay)
    // User expects to start talking right away in car
    if (_activeTrip != null && mounted) {
      // Use post-frame callback to ensure widget tree is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _launchVoiceAssistant();
      });
    }
  }

  void _launchVoiceAssistant() {
    if (_activeTrip == null) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VoiceAssistantScreen(
          trip: _activeTrip!,
          stops: _stops,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : _activeTrip == null
                ? _buildNoTripView()
                : _buildTripView(),
      ),
    );
  }

  Widget _buildNoTripView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.flight_takeoff,
            size: 80,
            color: Colors.white54,
          ),
          const SizedBox(height: 24),
          const Text(
            'No active trip today',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Plan a trip to get started',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripView() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(
                Icons.flight_takeoff,
                size: 32,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Text(
                'Trip to ${_activeTrip!.city}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Flight info
          _buildFlightCard(
            'Outbound',
            _activeTrip!.outboundFlight,
            _activeTrip!.departOrigin,
            _activeTrip!.arriveDestination,
            Icons.flight_takeoff,
          ),
          const SizedBox(height: 16),
          _buildFlightCard(
            'Return',
            _activeTrip!.returnFlight,
            _activeTrip!.departDestination,
            _activeTrip!.arriveOrigin,
            Icons.flight_land,
          ),

          const Spacer(),

          // Launch button
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton.icon(
              onPressed: _launchVoiceAssistant,
              icon: const Icon(Icons.mic, size: 28),
              label: const Text(
                'Launch Voice Assistant',
                style: TextStyle(fontSize: 20),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'Launching automatically...',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlightCard(
    String label,
    String flightNumber,
    String departure,
    String arrival,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  flightNumber,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$departure → $arrival',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
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

