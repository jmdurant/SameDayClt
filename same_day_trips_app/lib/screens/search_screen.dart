import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../services/amadeus_service.dart';
import '../models/trip.dart';
import '../models/stop.dart';
import '../models/flight_offer.dart';
import '../theme/app_colors.dart';
import '../theme/theme_provider.dart';
import '../services/user_profile_service.dart';
import '../models/user_profile.dart';
import 'results_screen.dart';
import 'voice_assistant_screen.dart';
import 'saved_agendas_screen.dart';
import 'route_viewer_screen.dart';
import 'profile_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum TripMode { sameDay, overnight, routeViewer }

class _SearchScreenState extends State<SearchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();
  final _amadeusService = AmadeusService();
  final _profileService = UserProfileService();

  // Trip mode
  TripMode _tripMode = TripMode.sameDay;

  // Form values
  String _origin = 'CLT';
  String _destination = 'ATL'; // For overnight mode
  DateTime _selectedDate = DateTime.now();
  DateTime? _returnDate; // For overnight mode
  int _earliestDepart = 5; // 5 AM - earliest departure time
  int _departBy = 9; // 9 AM - realistic for commercial flights
  int _returnAfter = 15;
  int _returnBy = 19;
  double _minGroundTime = 3.0;
  int _minDuration = 70; // filter out very short hops
  int _maxDuration = 204; // ~3.4 hours flight time
  final List<String> _selectedDestinations = [];
  final List<String> _selectedAirlines = [];
  final List<String> _airlineOptions = ['AA', 'DL', 'UA', 'WN', 'AS', 'B6', 'NK', 'F9'];

  // Available destinations for dropdown (loaded from Amadeus)
  List<Destination> _availableDestinations = [];
  bool _isLoadingDestinations = false;

  bool _isSearching = false;
  bool _isDetectingAirport = false;
  String? _detectError;
  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  UserProfile? _profile;
  Timer? _airportSearchDebounce;

  @override
  void initState() {
    super.initState();
    _originController.text = _origin;
    _destinationController.text = _destination;
    _loadProfileDefaults();
    _autoDetectHomeAirport();
  }

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    _airportSearchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadProfileDefaults() async {
    final profile = await _profileService.load();
    if (profile == null) return;
    _profile = profile;
    setState(() {
      if (profile.homeAirport != null && profile.homeAirport!.length == 3) {
        _origin = profile.homeAirport!.toUpperCase();
        _originController.text = _origin;
      }
      if (profile.preferredAirlines.isNotEmpty) {
        _selectedAirlines
          ..clear()
          ..addAll(profile.preferredAirlines.map((c) => c.toUpperCase()));
      }
      _earliestDepart = profile.earliestDepart ?? _earliestDepart;
      _departBy = profile.departBy ?? _departBy;
      _returnAfter = profile.returnAfter ?? _returnAfter;
      _returnBy = profile.returnBy ?? _returnBy;
      _minGroundTime = profile.minGroundTime ?? _minGroundTime;
      _minDuration = profile.minDuration ?? _minDuration;
      _maxDuration = profile.maxDuration ?? _maxDuration;
    });
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

      // Use Amadeus API to find nearest airport (replaces manual lookup!)
      final nearest = await _amadeusService.findNearestAirport(
        latitude: position.latitude,
        longitude: position.longitude,
        radiusKm: 100,
      );

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

  Future<void> _showAirportSearch({required bool isOrigin}) async {
    final TextEditingController queryController = TextEditingController();
    List<Destination> results = [];
    bool loading = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> runSearch(String q) async {
              if (q.length < 2) return;
              setState(() => loading = true);
              final res = await _amadeusService.searchAirports(keyword: q, limit: 10);
              setState(() {
                results = res;
                loading = false;
              });
            }

            return AlertDialog(
              title: const Text('Search Airports'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: queryController,
                    decoration: const InputDecoration(
                      hintText: 'Type city or airport code',
                    ),
                    onChanged: (value) {
                      _airportSearchDebounce?.cancel();
                      _airportSearchDebounce = Timer(const Duration(milliseconds: 350), () {
                        runSearch(value.trim());
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  if (loading) const LinearProgressIndicator(minHeight: 2),
                  SizedBox(
                    width: double.maxFinite,
                    height: 240,
                    child: results.isEmpty && !loading
                        ? const Center(child: Text('No results yet'))
                        : ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (context, index) {
                              final d = results[index];
                              return ListTile(
                                title: Text('${d.code} • ${d.city}'),
                                onTap: () {
                                  Navigator.pop(context, d.code);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    ).then((value) {
      if (value is String && value.length == 3) {
        setState(() {
          if (isOrigin) {
            _origin = value.toUpperCase();
            _originController.text = _origin;
          } else {
            _destination = value.toUpperCase();
            _destinationController.text = _destination;
          }
        });
      }
    });
  }

  /// Check if we should use destination dropdown (only for non-AA/DL airlines)
  /// Amadeus doesn't return AA/DL at this tier level
  bool get _shouldUseDestinationDropdown {
    return false; // Disable airline-filtered destination dropdown
  }

  /// Load available destinations from Amadeus based on origin
  Future<void> _loadDestinations() async {
    if (_origin.length != 3) return;

    setState(() => _isLoadingDestinations = true);

    try {
      final destinations = await _amadeusService.discoverDestinations(
        origin: _origin,
        date: DateFormat('yyyy-MM-dd').format(_selectedDate),
        domesticOnly: true,
      );

      setState(() {
        _availableDestinations = destinations;
        _isLoadingDestinations = false;
      });
    } catch (e) {
      setState(() {
        _availableDestinations = [];
        _isLoadingDestinations = false;
      });
      print('Failed to load destinations: $e');
    }
  }

  void _searchTrips() {
    if (!_formKey.currentState!.validate()) return;

    // Route Viewer mode: Navigate to grid screen
    if (_tripMode == TripMode.routeViewer) {
      final weekStart = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1)); // Get Monday
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RouteViewerScreen(
            origin: _origin,
            destination: _destination,
            weekStart: weekStart,
            airlineFilters: _selectedAirlines.isEmpty ? null : _selectedAirlines,
          ),
        ),
      );
      return;
    }

    print('🔍 Starting search...');
    print('  Mode: ${_tripMode == TripMode.sameDay ? 'Same-Day' : 'Overnight'}');
    print('  Origin: $_origin');
    if (_tripMode == TripMode.overnight) {
      print('  Destination: $_destination');
    }
    print('  Date: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}');
    if (_tripMode == TripMode.overnight && _returnDate != null) {
      print('  Return: ${DateFormat('yyyy-MM-dd').format(_returnDate!)}');
    }
    print('  Depart window: $_earliestDepart:00 - $_departBy:00');
    print('  Return window: $_returnAfter:00 - $_returnBy:00');
    print('  Min ground time: $_minGroundTime hrs');
    print('  Min duration: $_minDuration min');
    print('  Max duration: $_maxDuration min');
    if (_selectedAirlines.isNotEmpty) {
      print('  Airlines: ${_selectedAirlines.join(',')}');
    }

    setState(() => _isSearching = true);

    try {
      print('📡 Starting streaming API call...');

      // For overnight mode, search only the specific destination
      // For same-day mode, discover all destinations
      final searchDestinations = _tripMode == TripMode.overnight
          ? [_destination]
          : (_selectedDestinations.isEmpty ? null : _selectedDestinations);

      final tripStream = _apiService.searchTripsStream(
        origin: _origin,
        date: DateFormat('yyyy-MM-dd').format(_selectedDate),
        returnDate: _returnDate != null ? DateFormat('yyyy-MM-dd').format(_returnDate!) : null,
        earliestDepart: _earliestDepart,
        departBy: _departBy,
        returnAfter: _returnAfter,
        returnBy: _returnBy,
        minGroundTime: _minGroundTime,
        minDuration: _minDuration,
        maxDuration: _maxDuration,
        airlines: _selectedAirlines.isEmpty ? null : _selectedAirlines,
        destinations: searchDestinations,
      );

      if (!mounted) return;

      print('📱 Navigating to results screen IMMEDIATELY...');
      // Navigate immediately with stream - results will appear as they're found!
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ResultsScreen(
            tripStream: tripStream,
            searchParams: {
              'origin': _origin,
              'date': DateFormat('MMM d, yyyy').format(_selectedDate),
              'departBy': _departBy,
              'returnBy': _returnBy,
            },
          ),
        ),
      ).then((_) {
        // Reset searching state when user returns
        if (mounted) {
          setState(() => _isSearching = false);
        }
      });
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
            icon: const Icon(Icons.person),
            tooltip: 'Profile & Defaults',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
              if (result is UserProfile) {
                _loadProfileDefaults();
              }
            },
          ),
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
              if (_isDetectingAirport)
                LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: context.blueTint,
                ),

              // Trip Mode Toggle
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _tripMode = TripMode.sameDay;
                          // Reset return date to same day for same-day mode
                          _returnDate = null;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _tripMode == TripMode.sameDay
                            ? context.primaryColor
                            : context.surfaceColor,
                        foregroundColor: _tripMode == TripMode.sameDay
                            ? Colors.white
                            : context.textPrimary,
                        padding: const EdgeInsets.all(12),
                        elevation: _tripMode == TripMode.sameDay ? 8 : 1,
                      ),
                      child: const Text('Same Day', textAlign: TextAlign.center),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _tripMode = TripMode.overnight;
                          // Initialize return date if not set
                          _returnDate ??= _selectedDate.add(const Duration(days: 1));
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _tripMode == TripMode.overnight
                            ? context.primaryColor
                            : context.surfaceColor,
                        foregroundColor: _tripMode == TripMode.overnight
                            ? Colors.white
                            : context.textPrimary,
                        padding: const EdgeInsets.all(12),
                        elevation: _tripMode == TripMode.overnight ? 8 : 1,
                      ),
                      child: const Text('Overnight', textAlign: TextAlign.center),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _tripMode = TripMode.routeViewer;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _tripMode == TripMode.routeViewer
                            ? context.primaryColor
                            : context.surfaceColor,
                        foregroundColor: _tripMode == TripMode.routeViewer
                            ? Colors.white
                            : context.textPrimary,
                        padding: const EdgeInsets.all(12),
                        elevation: _tripMode == TripMode.routeViewer ? 8 : 1,
                      ),
                      child: const Text('Route View', textAlign: TextAlign.center),
                    ),
                  ),
                ],
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

              // Origin Airport (and Destination for overnight/route viewer modes)
              if (_tripMode == TripMode.sameDay)
                TextFormField(
                  controller: _originController,
                  decoration: InputDecoration(
                    labelText: 'Your Home Airport',
                    hintText: 'e.g., CLT, ATL, LAX',
                    prefixIcon: const Icon(Icons.home),
                    border: const OutlineInputBorder(),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isDetectingAirport)
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.my_location),
                          tooltip: 'Use current location',
                          onPressed: _autoDetectHomeAirport,
                        ),
                      IconButton(
                        icon: const Icon(Icons.search),
                        tooltip: 'Search airports',
                        onPressed: () => _showAirportSearch(isOrigin: true),
                      ),
                    ],
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
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _originController,
                        decoration: InputDecoration(
                          labelText: 'Your Home Airport',
                          hintText: 'e.g., CLT',
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
                          // Load destinations when origin changes (for dropdown mode)
                          if (_shouldUseDestinationDropdown && upper.length == 3) {
                            _loadDestinations();
                          }
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
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _destinationController,
                        decoration: InputDecoration(
                          labelText: 'Destination Airport',
                          hintText: 'e.g., ATL',
                          prefixIcon: const Icon(Icons.flight_land),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.search),
                            tooltip: 'Search airports',
                            onPressed: () => _showAirportSearch(isOrigin: false),
                          ),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 3,
                        onChanged: (value) {
                          final upper = value.toUpperCase();
                          if (upper != value) {
                            _destinationController.value = _destinationController.value.copyWith(
                              text: upper,
                              selection: TextSelection.collapsed(offset: upper.length),
                            );
                          }
                          _destination = upper;
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter destination code';
                          }
                          if (value.length != 3) {
                            return 'Airport code must be 3 letters';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
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

              // Date Picker(s) or Week Selector
              if (_tripMode == TripMode.sameDay)
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
                )
              else if (_tripMode == TripMode.routeViewer)
                // Week Selector for Route Viewer
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios),
                      onPressed: () {
                        setState(() {
                          _selectedDate = _selectedDate.subtract(const Duration(days: 7));
                        });
                      },
                      tooltip: 'Previous week',
                    ),
                    Expanded(
                      child: InkWell(
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
                            labelText: 'Week Starting',
                            prefixIcon: Icon(Icons.date_range),
                            border: OutlineInputBorder(),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  () {
                                    final weekStart = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
                                    final weekEnd = weekStart.add(const Duration(days: 6));
                                    return '${DateFormat('MMM d').format(weekStart)} - ${DateFormat('MMM d, yyyy').format(weekEnd)}';
                                  }(),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios),
                      onPressed: () {
                        setState(() {
                          _selectedDate = _selectedDate.add(const Duration(days: 7));
                        });
                      },
                      tooltip: 'Next week',
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() {
                              _selectedDate = picked;
                              // Auto-adjust return date if it's before departure
                              if (_returnDate == null || _returnDate!.isBefore(picked)) {
                                _returnDate = picked.add(const Duration(days: 1));
                              }
                            });
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
                              Flexible(
                                child: Text(
                                  DateFormat('MMM d, yyyy').format(_selectedDate),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _returnDate ?? _selectedDate.add(const Duration(days: 1)),
                            firstDate: _selectedDate,
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() => _returnDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Return Date',
                            prefixIcon: Icon(Icons.event),
                            border: OutlineInputBorder(),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  DateFormat('MMM d, yyyy').format(
                                    _returnDate ?? _selectedDate.add(const Duration(days: 1)),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 24),

              // Airline Filter
              Text(
                'Preferred Airlines (optional)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _airlineOptions.map((code) {
                  final selected = _selectedAirlines.contains(code);
                  return FilterChip(
                    label: Text(code),
                    selected: selected,
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedAirlines.add(code);
                        } else {
                          _selectedAirlines.remove(code);
                        }
                      });
                      // Reload destinations when airline filter changes
                      if (_shouldUseDestinationDropdown && _origin.length == 3) {
                        _loadDestinations();
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Time Preferences (hidden for Route Viewer)
              if (_tripMode != TripMode.routeViewer) ...[
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
              ], // End of time preferences section

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
