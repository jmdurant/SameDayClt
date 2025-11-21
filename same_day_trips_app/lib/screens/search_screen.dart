import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../models/trip.dart';
import '../models/stop.dart';
import '../theme/app_colors.dart';
import '../theme/theme_provider.dart';
import '../utils/airport_lookup.dart';
import 'results_screen.dart';
import 'voice_assistant_screen.dart';
import 'saved_agendas_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();

  // Form values
  String _origin = 'CLT';
  DateTime _selectedDate = DateTime.now();
  int _earliestDepart = 5; // 5 AM - earliest departure time
  int _departBy = 9; // 9 AM - realistic for commercial flights
  int _returnAfter = 15;
  int _returnBy = 19;
  double _minGroundTime = 3.0;
  int _minDuration = 50; // filter out very short hops
  int _maxDuration = 204; // ~3.4 hours flight time
  final List<String> _selectedDestinations = [];

  bool _isSearching = false;
  bool _isDetectingAirport = false;
  String? _detectError;
  final TextEditingController _originController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _originController.text = _origin;
    _autoDetectHomeAirport();
  }

  @override
  void dispose() {
    _originController.dispose();
    super.dispose();
  }

  // Helper function to convert decimal hours to "Xh Ymin" format
  String _formatHours(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    if (m == 0) {
      return '${h}h';
    }
    return '${h}h ${m}min';
  }

  Future<void> _autoDetectHomeAirport() async {
    setState(() {
      _isDetectingAirport = true;
      _detectError = null;
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          setState(() {
            _detectError = 'Location permission denied';
            _isDetectingAirport = false;
          });
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final nearest = findNearestAirport(position.latitude, position.longitude);
      if (nearest != null) {
        setState(() {
          _origin = nearest;
          _originController.text = nearest;
          _isDetectingAirport = false;
        });
      } else {
        setState(() {
          _detectError = 'Could not find nearby airport';
          _isDetectingAirport = false;
        });
      }
    } catch (e) {
      setState(() {
        _detectError = 'Auto-detect failed: $e';
        _isDetectingAirport = false;
      });
    }
  }


  Future<void> _searchTrips() async {
    if (!_formKey.currentState!.validate()) return;

    print('🔍 Starting search...');
    print('  Origin: $_origin');
    print('  Date: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}');
    print('  Depart window: $_earliestDepart:00 - $_departBy:00');
    print('  Return window: $_returnAfter:00 - $_returnBy:00');
    print('  Min ground time: $_minGroundTime hrs');
    print('  Min duration: $_minDuration min');
    print('  Max duration: $_maxDuration min');

    setState(() => _isSearching = true);

    try {
      print('📡 Calling API...');
      final trips = await _apiService.searchTrips(
        origin: _origin,
        date: DateFormat('yyyy-MM-dd').format(_selectedDate),
        earliestDepart: _earliestDepart,
        departBy: _departBy,
        returnAfter: _returnAfter,
        returnBy: _returnBy,
        minGroundTime: _minGroundTime,
        minDuration: _minDuration,
        maxDuration: _maxDuration,
        destinations: _selectedDestinations.isEmpty ? null : _selectedDestinations,
      );

      print('✅ API returned ${trips.length} trips');

      if (!mounted) return;

      print('📱 Navigating to results screen...');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ResultsScreen(
            trips: trips,
            searchParams: {
              'origin': _origin,
              'date': DateFormat('MMM d, yyyy').format(_selectedDate),
              'departBy': _departBy,
              'returnBy': _returnBy,
            },
          ),
        ),
      );
    } catch (e) {
      print('❌ Search failed: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Search failed: ${e.toString()}'),
          backgroundColor: context.errorColor,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Same-Day Business Trips'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: Icon(
              context.isDarkMode ? Icons.light_mode : Icons.dark_mode,
            ),
            tooltip: context.isDarkMode ? 'Switch to light mode' : 'Switch to dark mode',
            onPressed: () {
              Provider.of<ThemeProvider>(context, listen: false).toggleTheme();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Icon(Icons.flight_takeoff, size: 48, color: context.primaryColor),
                      const SizedBox(height: 8),
                      Text(
                        'Plan Your Day Trip',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Meet clients in person and still be home for dinner',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Saved Agendas Button
              Card(
                elevation: 4,
                color: context.greenTint,
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SavedAgendasScreen(),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: context.successColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.bookmark,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Saved Agendas',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: context.successColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'View your saved trip agendas',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: context.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: context.successColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Voice Assistant Quick Access Button
              Card(
                elevation: 4,
                color: context.blueTint,
                child: InkWell(
                  onTap: () {
                    // Create a minimal mock trip for today with no specific destination
                    final mockTrip = Trip(
                      city: 'Your Day',
                      origin: _origin.isEmpty ? 'CLT' : _origin,
                      destination: 'Anywhere',
                      date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
                      outboundFlight: '',
                      outboundStops: 0,
                      departOrigin: '',
                      arriveDestination: '',
                      outboundDuration: '',
                      outboundPrice: 0.0,
                      returnFlight: '',
                      returnStops: 0,
                      departDestination: '',
                      arriveOrigin: '',
                      returnDuration: '',
                      returnPrice: 0.0,
                      groundTimeHours: 0.0,
                      groundTime: '',
                      totalFlightCost: 0.0,
                      totalTripTime: '',
                    );

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VoiceAssistantScreen(
                          trip: mockTrip,
                          stops: const [],
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: context.primaryColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.mic,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Voice Assistant',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: context.primaryColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Ask about weather, traffic, calendar, or plan your day',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: context.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: context.primaryColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Origin Airport
              TextFormField(
                controller: _originController,
                decoration: InputDecoration(
                  labelText: 'Your Home Airport',
                  hintText: 'e.g., CLT, ATL, LAX',
                  prefixIcon: const Icon(Icons.home),
                  border: const OutlineInputBorder(),
                  suffixIcon: _isDetectingAirport
                      ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.my_location),
                          tooltip: 'Use current location',
                          onPressed: _autoDetectHomeAirport,
                        ),
                ),
                textCapitalization: TextCapitalization.characters,
                maxLength: 3,
                onChanged: (value) {
                  final upper = value.toUpperCase();
                  if (upper != value) {
                    _originController.value = _originController.value.copyWith(
                      text: upper,
                      selection: TextSelection.collapsed(offset: upper.length),
                    );
                  }
                  _origin = upper;
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your airport code';
                  }
                  if (value.length != 3) {
                    return 'Airport code must be 3 letters';
                  }
                  return null;
                },
              ),
              if (_detectError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    _detectError!,
                    style: TextStyle(color: context.errorColor, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 16),

              // Date Picker
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = picked);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Travel Date',
                    prefixIcon: Icon(Icons.calendar_today),
                    border: OutlineInputBorder(),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(DateFormat('EEEE, MMM d, yyyy').format(_selectedDate)),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Time Preferences
              Text(
                'Travel Schedule',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),

              // Departure Window
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _earliestDepart,
                      decoration: const InputDecoration(
                        labelText: 'Earliest Departure',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.wb_twilight),
                      ),
                      items: List.generate(12, (i) => i + 5)
                          .map((hour) => DropdownMenuItem(
                                value: hour,
                                child: Text('${hour}:00 AM'),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() => _earliestDepart = value!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _departBy,
                      decoration: const InputDecoration(
                        labelText: 'Latest Departure',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.flight_takeoff),
                      ),
                      items: List.generate(12, (i) => i + 5)
                          .map((hour) => DropdownMenuItem(
                                value: hour,
                                child: Text('${hour}:00 AM'),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() => _departBy = value!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _returnAfter,
                      decoration: const InputDecoration(
                        labelText: 'Earliest Home Arrival',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.flight_land),
                      ),
                      items: List.generate(10, (i) => i + 14)
                          .map((hour) => DropdownMenuItem(
                                value: hour,
                                child: Text('${hour > 12 ? hour - 12 : hour}:00 ${hour >= 12 ? 'PM' : 'AM'}'),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() => _returnAfter = value!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _returnBy,
                      decoration: const InputDecoration(
                        labelText: 'Latest Home Arrival',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.home),
                      ),
                      items: List.generate(8, (i) => i + 17)
                          .map((hour) => DropdownMenuItem(
                                value: hour,
                                child: Text('${hour > 12 ? hour - 12 : hour}:00 ${hour >= 12 ? 'PM' : 'AM'}'),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() => _returnBy = value!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Ground Time
              Text(
                'Minimum Meeting Time: ${_formatHours(_minGroundTime)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                value: _minGroundTime,
                min: 2.0,
                max: 8.0,
                divisions: 12,
                label: _formatHours(_minGroundTime),
                onChanged: (value) => setState(() => _minGroundTime = value),
              ),
              const SizedBox(height: 16),

              // Min Flight Duration
              Text(
                'Minimum Flight Time: ${_formatHours(_minDuration / 60)} each way',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                value: _minDuration.toDouble(),
                min: 30,
                max: 180,
                divisions: 15,
                label: _formatHours(_minDuration / 60),
                onChanged: (value) => setState(() {
                  _minDuration = value.toInt();
                  if (_maxDuration < _minDuration) {
                    _maxDuration = _minDuration;
                  }
                }),
              ),
              const SizedBox(height: 16),

              // Max Flight Duration
              Text(
                'Maximum Flight Time: ${_formatHours(_maxDuration / 60)} each way',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                value: _maxDuration.toDouble(),
                min: _minDuration.toDouble(),
                max: 300,
                divisions: 24,
                label: _formatHours(_maxDuration / 60),
                onChanged: (value) => setState(() => _maxDuration = value.toInt()),
              ),
              const SizedBox(height: 24),

              // Search Button
              ElevatedButton.icon(
                onPressed: _isSearching ? null : _searchTrips,
                icon: _isSearching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_isSearching ? 'Searching...' : 'Find Trips'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(height: 16),

              // Info Card
              Card(
                color: context.blueTint,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: context.primaryColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Search may take 30-60 seconds as we check real-time flight availability',
                          style: TextStyle(
                            color: context.primaryColor,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
