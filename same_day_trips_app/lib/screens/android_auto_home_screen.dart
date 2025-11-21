import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/trip.dart';
import '../models/stop.dart';
import '../theme/app_colors.dart';
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
    
    // Use today's date in yyyy-MM-dd format for FlightAware API compatibility (10-day limit)
    final today = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(today);
    
    setState(() {
      _activeTrip = Trip(
        city: 'Atlanta',
        origin: 'CLT',
        destination: 'ATL',
        date: dateStr,
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
    // Android Auto uses dark theme but should respect system theme
    final backgroundColor = context.isDarkMode
        ? Colors.black
        : Theme.of(context).colorScheme.background;
    final progressColor = context.textPrimary;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(color: progressColor),
              )
            : _activeTrip == null
                ? _buildNoTripView()
                : _buildTripView(),
      ),
    );
  }

  Widget _buildNoTripView() {
    final iconColor = context.textSecondary;
    final titleColor = context.textPrimary;
    final subtitleColor = context.textSecondary;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.flight_takeoff,
            size: 80,
            color: iconColor,
          ),
          const SizedBox(height: 24),
          Text(
            'No active trip today',
            style: TextStyle(
              color: titleColor,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Plan a trip to get started',
            style: TextStyle(
              color: subtitleColor,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripView() {
    final headerIconColor = context.textPrimary;
    final headerTextColor = context.textPrimary;
    final buttonBackgroundColor = context.infoColor;
    final buttonTextColor = context.isDarkMode
        ? AppColors.textPrimaryDark
        : AppColors.textPrimaryLight;
    final launchingTextColor = context.textSecondary;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.flight_takeoff,
                size: 32,
                color: headerIconColor,
              ),
              const SizedBox(width: 12),
              Text(
                'Trip to ${_activeTrip!.city}',
                style: TextStyle(
                  color: headerTextColor,
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
                backgroundColor: buttonBackgroundColor,
                foregroundColor: buttonTextColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Launching automatically...',
              style: TextStyle(
                color: launchingTextColor,
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
    // High contrast colors for Android Auto display requirements
    final cardBackgroundColor = context.isDarkMode
        ? Colors.white.withOpacity(0.12)
        : Theme.of(context).colorScheme.surface;
    final iconColor = context.textPrimary;
    final labelColor = context.textSecondary;
    final flightNumberColor = context.textPrimary;
    final timesColor = context.textPrimary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBackgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  flightNumber,
                  style: TextStyle(
                    color: flightNumberColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$departure → $arrival',
                  style: TextStyle(
                    color: timesColor,
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

