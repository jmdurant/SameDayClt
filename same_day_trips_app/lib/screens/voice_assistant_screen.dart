import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/timezone.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/trip.dart';
import '../models/stop.dart';
import '../services/navigation_service.dart';

class VoiceAssistantScreen extends StatefulWidget {
  final Trip trip;
  final List<Stop> stops;

  const VoiceAssistantScreen({
    super.key,
    required this.trip,
    required this.stops,
  });

  @override
  State<VoiceAssistantScreen> createState() => _VoiceAssistantScreenState();
}

class _VoiceAssistantScreenState extends State<VoiceAssistantScreen> with WidgetsBindingObserver {
  InAppWebViewController? _controller;
  Position? _currentLocation;
  String? _currentAddress;
  bool _isLoading = true;
  List<Event> _todaysEvents = [];

  Timer? _proactiveCheckTimer;
  StreamSubscription<Position>? _locationSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Enable landscape orientation for better Android Auto experience
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Initialize location and calendar FIRST, then WebView
    _initializeLocationAndCalendar();
    _startProactiveChecks();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      print('📱 App resumed - refreshing location');
      // Re-send current location to WebView when app resumes
      if (_currentLocation != null && _controller != null) {
        _updateLocationInWebView(_currentLocation!);
      }
    }
  }
  
  Future<void> _initializeLocationAndCalendar() async {
    // Initialize location and calendar first
    await _initializeLocation();
    await _initializeCalendar();
    
    print('📍 Location: ${_currentLocation?.latitude}, ${_currentLocation?.longitude}');
    print('📅 Calendar events: ${_todaysEvents.length}');
    
    // NOW set loading to false so WebView can build with location data
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _proactiveCheckTimer?.cancel();
    _locationSubscription?.cancel();
    // Reset orientation preferences when leaving the screen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  void _startProactiveChecks() {
    // Check every 5 minutes for proactive suggestions
    _proactiveCheckTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _checkForProactivePrompts();
    });
  }

  void _checkForProactivePrompts() {
    if (!mounted) return;

    final now = DateTime.now();
    
    // Check if near a calendar event
    for (var event in _todaysEvents) {
      if (event.start == null) continue;
      
      final minutesUntilEvent = event.start!.difference(now).inMinutes;
      
      // Alert 30 minutes before event
      if (minutesUntilEvent > 25 && minutesUntilEvent <= 30) {
        _sendProactiveMessage(
          "You have '${event.title}' in 30 minutes${event.location != null ? ' at ${event.location}' : ''}. Need help getting there?"
        );
        break;
      }
      
      // Alert if running late
      if (minutesUntilEvent > 0 && minutesUntilEvent <= 10 && _currentLocation != null && event.location != null) {
        _sendProactiveMessage(
          "Your event '${event.title}' starts in $minutesUntilEvent minutes. Should I check traffic?"
        );
        break;
      }
    }
    
    // Check if it's lunch time (11:30-12:30) and no lunch event
    final hour = now.hour;
    final minute = now.minute;
    if (hour == 11 && minute >= 30 || hour == 12 && minute <= 30) {
      final hasLunchEvent = _todaysEvents.any((e) {
        final title = e.title?.toLowerCase() ?? '';
        return title.contains('lunch') || title.contains('eat');
      });
      
      if (!hasLunchEvent) {
        _sendProactiveMessage(
          "It's lunchtime! Want me to find nearby restaurants?"
        );
      }
    }
  }

  void _sendProactiveMessage(String message) {
    _controller?.evaluateJavascript(source: '''
      if (window.receiveProactiveMessage) {
        window.receiveProactiveMessage("$message");
      }
    ''');
  }

  Future<void> _initializeCalendar() async {
    try {
      final DeviceCalendarPlugin deviceCalendarPlugin = DeviceCalendarPlugin();
      
      // Always request permissions explicitly (don't just check)
      print('📅 Requesting calendar permissions...');
      var permissionsGranted = await deviceCalendarPlugin.requestPermissions();
      
      if (!permissionsGranted.isSuccess || !permissionsGranted.data!) {
        print('! Calendar permissions denied');
        return;
      }
      
      print('✅ Calendar permissions granted');

      // Get all calendars
      final calendarsResult = await deviceCalendarPlugin.retrieveCalendars();
      if (!calendarsResult.isSuccess || calendarsResult.data == null) {
        print('⚠️ Could not retrieve calendars');
        return;
      }

      print('📅 Found ${calendarsResult.data!.length} calendars');

      // Get today's events from all calendars
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

      List<Event> allEvents = [];
      for (var calendar in calendarsResult.data!) {
        final eventsResult = await deviceCalendarPlugin.retrieveEvents(
          calendar.id,
          RetrieveEventsParams(startDate: startOfDay, endDate: endOfDay),
        );
        if (eventsResult.isSuccess && eventsResult.data != null) {
          allEvents.addAll(eventsResult.data!);
        }
      }

      // Sort by start time
      allEvents.sort((a, b) {
        final aStart = a.start ?? DateTime.now();
        final bStart = b.start ?? DateTime.now();
        return aStart.compareTo(bStart);
      });

      setState(() {
        _todaysEvents = allEvents;
      });

      print('📅 Loaded ${allEvents.length} calendar events for today');
    } catch (e) {
      print('⚠️ Calendar error: $e');
    }
  }

  Future<void> _makePhoneCall(String phoneNumber, String placeName) async {
    try {
      // Clean the phone number (remove formatting)
      final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
      final telUrl = 'tel:$cleanNumber';
      
      print('📞 Launching phone dialer: $telUrl');
      
      if (await canLaunchUrl(Uri.parse(telUrl))) {
        await launchUrl(
          Uri.parse(telUrl),
          mode: LaunchMode.externalApplication,
        );
        
        // Show confirmation
        if (mounted) {
          final nameText = placeName.isNotEmpty ? ' $placeName' : '';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Calling$nameText...'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        print('⚠️ Cannot launch phone dialer for: $telUrl');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Unable to open phone dialer'),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('⚠️ Error launching phone dialer: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initiate call'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _addCalendarEvent({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    String? location,
    String? description,
  }) async {
    try {
      final DeviceCalendarPlugin deviceCalendarPlugin = DeviceCalendarPlugin();
      
      // Get all calendars
      final calendarsResult = await deviceCalendarPlugin.retrieveCalendars();
      if (!calendarsResult.isSuccess || calendarsResult.data == null || calendarsResult.data!.isEmpty) {
        print('⚠️ No calendars available to add event');
        return;
      }

      // Find the primary calendar (or use the first writable one)
      Calendar? targetCalendar;
      for (var calendar in calendarsResult.data!) {
        if (calendar.isDefault == true || targetCalendar == null) {
          targetCalendar = calendar;
        }
        if (calendar.isDefault == true) break; // Prefer default calendar
      }

      if (targetCalendar == null) {
        print('⚠️ No writable calendar found');
        return;
      }

      print('📅 Adding event to calendar: ${targetCalendar.name}');

      // Create the event
      final Event event = Event(
        targetCalendar.id,
        title: title,
        start: TZDateTime.from(startTime, getLocation('America/New_York')),
        end: TZDateTime.from(endTime, getLocation('America/New_York')),
        location: location,
        description: description,
      );

      // Add the event
      final createEventResult = await deviceCalendarPlugin.createOrUpdateEvent(event);
      
      if (createEventResult?.isSuccess == true) {
        print('✅ Successfully added calendar event: $title');
        
        // Show a snackbar confirmation to the user
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added "$title" to your calendar'),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        print('⚠️ Failed to add calendar event: ${createEventResult?.errors}');
      }
    } catch (e) {
      print('⚠️ Error adding calendar event: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add event to calendar'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _reverseGeocode(Position position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        // Build a nice address string
        String address = '';
        if (place.street != null && place.street!.isNotEmpty) {
          address += place.street!;
        }
        if (place.subLocality != null && place.subLocality!.isNotEmpty) {
          if (address.isNotEmpty) address += ', ';
          address += place.subLocality!;
        }
        if (place.locality != null && place.locality!.isNotEmpty) {
          if (address.isNotEmpty) address += ', ';
          address += place.locality!;
        }
        
        setState(() {
          _currentAddress = address;
        });
        print('📍 Reverse geocoded address: $address');
      }
    } catch (e) {
      print('⚠️ Reverse geocoding failed: $e');
    }
  }

  Future<void> _initializeLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('⚠️ Location service not enabled, using fallback location');
        // Use Charlotte, NC as fallback for testing
        setState(() {
          _currentLocation = Position(
            latitude: 35.2271,
            longitude: -80.8431,
            timestamp: DateTime.now(),
            accuracy: 0,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          );
        });
        return;
      }

      // Check permission (already requested in main.dart, so just check here)
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        print('⚠️ Location permission denied, using fallback location');
        // Use Charlotte, NC as fallback
        setState(() {
          _currentLocation = Position(
            latitude: 35.2271,
            longitude: -80.8431,
            timestamp: DateTime.now(),
            accuracy: 0,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          );
        });
        return;
      }

      // FAST: Try to get last known position first (instant, coarse location)
      Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        print('📍 Got last known location (coarse): ${lastKnown.latitude}, ${lastKnown.longitude}');
        setState(() {
          _currentLocation = lastKnown;
        });
        // Reverse geocode in background
        _reverseGeocode(lastKnown);
        // This allows WebView to load immediately with coarse location
      }

      // ACCURATE: Get current high-accuracy position (may take 1-3 seconds)
      // This happens in background after WebView loads
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      print('📍 Got accurate GPS location: ${position.latitude}, ${position.longitude}');
      setState(() {
        _currentLocation = position;
      });

      // Reverse geocode accurate location
      await _reverseGeocode(position);
      
      // Update WebView with accurate location and address
      _updateLocationInWebView(position);

      // Update location periodically - store subscription for lifecycle management
      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 100, // Update every 100 meters
        ),
      ).listen((Position position) {
        print('📍 Location updated: ${position.latitude}, ${position.longitude}');
        if (mounted) {
        setState(() {
          _currentLocation = position;
        });
        _reverseGeocode(position);
        _updateLocationInWebView(position);
        }
      });
    } catch (e) {
      print('⚠️ Location error: $e, using fallback location');
      // Use Charlotte, NC as fallback
      setState(() {
        _currentLocation = Position(
          latitude: 35.2271,
          longitude: -80.8431,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
      });
    }
  }

  void _setupJavaScriptChannels() {
    // Set up navigation channel for voice assistant to call Google Maps
    _controller?.evaluateJavascript(source: '''
      window.launchNavigation = async function(destination, waypoints) {
        console.log('🗺️ Launching navigation:', destination, waypoints);
        // Flutter will intercept this
        return true;
      };
    ''');
  }

  Uri _buildWebViewUrl() {
    print('🔧 DEBUG: Building WebView URL...');
    print('🔧 DEBUG: _currentLocation = $_currentLocation');
    print('🔧 DEBUG: lat = ${_currentLocation?.latitude}, lng = ${_currentLocation?.longitude}');
    
    // Build URL with trip context and location
    final params = <String, String>{
      // Cache busting parameter to force reload of new version
      'v': DateTime.now().millisecondsSinceEpoch.toString(),
      
      // Basic trip info
      'city': widget.trip.city,
      'origin': widget.trip.origin,
      'dest': widget.trip.destination,
      'date': widget.trip.date,
      'groundTime': widget.trip.groundTimeHours.toString(),

      // Outbound flight details
      'outboundFlight': widget.trip.outboundFlight,
      'departOrigin': widget.trip.departOrigin,
      'arriveDestination': widget.trip.arriveDestination,
      'outboundDuration': widget.trip.outboundDuration,

      // Return flight details
      'returnFlight': widget.trip.returnFlight,
      'departDestination': widget.trip.departDestination,
      'arriveOrigin': widget.trip.arriveOrigin,
      'returnDuration': widget.trip.returnDuration,
    };

    if (_currentLocation != null) {
      print('✅ DEBUG: Adding location to URL params');
      params['lat'] = _currentLocation!.latitude.toString();
      params['lng'] = _currentLocation!.longitude.toString();
      if (_currentAddress != null) {
        params['address'] = _currentAddress!;
        print('✅ DEBUG: Adding address to URL params: $_currentAddress');
      }
    } else {
      print('❌ DEBUG: _currentLocation is NULL - location will NOT be in URL!');
    }

    // Add stops information as JSON
    if (widget.stops.isNotEmpty) {
      final stopsData = widget.stops.map((stop) => {
        'name': stop.name,
        'address': stop.address,
        'duration': stop.durationMinutes,
        if (stop.latitude != null) 'lat': stop.latitude,
        if (stop.longitude != null) 'lng': stop.longitude,
      }).toList();

      params['stops'] = jsonEncode(stopsData);
    }

    // Add calendar events as JSON
    if (_todaysEvents.isNotEmpty) {
      final eventsData = _todaysEvents.map((event) {
        final start = event.start;
        final end = event.end;
        return {
          'title': event.title ?? 'Untitled Event',
          'start': start?.toIso8601String(),
          'end': end?.toIso8601String(),
          if (event.location != null && event.location!.isNotEmpty) 
            'location': event.location,
          if (event.description != null && event.description!.isNotEmpty)
            'description': event.description,
        };
      }).toList();

      params['calendar'] = jsonEncode(eventsData);
    }

    return Uri.parse('https://samedaytrips.web.app').replace(queryParameters: params);
  }

  void _updateLocationInWebView(Position position) {
    // Send location update to web app via JavaScript
    _controller?.evaluateJavascript(source: '''
      if (window.updateLocation) {
        window.updateLocation(${position.latitude}, ${position.longitude});
      }
    ''');
  }

  void _updateCalendarInWebView() {
    if (_todaysEvents.isEmpty) return;
    
    final eventsData = _todaysEvents.map((event) {
      final start = event.start;
      final end = event.end;
      return {
        'title': event.title ?? 'Untitled Event',
        'start': start?.toIso8601String(),
        'end': end?.toIso8601String(),
        if (event.location != null && event.location!.isNotEmpty) 
          'location': event.location,
        if (event.description != null && event.description!.isNotEmpty)
          'description': event.description,
      };
    }).toList();

    final calendarJson = jsonEncode(eventsData).replaceAll("'", "\\'");
    
    _controller?.evaluateJavascript(source: '''
      if (window.updateCalendar) {
        window.updateCalendar($calendarJson);
      }
    ''');
  }

  @override
  Widget build(BuildContext context) {
    // Don't build WebView until location is ready
    if (_isLoading) {
    return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Initializing location and calendar...'),
            ],
          ),
        ),
      );
    }
    
    final url = _buildWebViewUrl();
    
    return Scaffold(
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri.uri(url)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              javaScriptCanOpenWindowsAutomatically: true,
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
              print('🌐 InAppWebView created');
              
              // Add JavaScript handler for navigation
              controller.addJavaScriptHandler(
                handlerName: 'FlutterNavigation',
                callback: (args) async {
                  try {
                    final data = args[0];
                    final String destination = data['destination'] ?? '';
                    final List<String> waypoints = data['waypoints'] != null 
                        ? List<String>.from(data['waypoints']) 
                        : [];
                    
                    if (destination.isNotEmpty) {
                      if (waypoints.isEmpty) {
                        await NavigationService.launchNavigation(destination);
                      } else {
                        await NavigationService.launchNavigationWithWaypoints(
                          destination: destination,
                          waypoints: waypoints,
                        );
                      }
                    }
                  } catch (e) {
                    print('⚠️ Error handling navigation request: $e');
                  }
                },
              );
              
              // Add JavaScript handler for adding calendar events
              controller.addJavaScriptHandler(
                handlerName: 'FlutterCalendar',
                callback: (args) async {
                  try {
                    final data = args[0];
                    final String title = data['title'] ?? '';
                    final String startTimeStr = data['startTime'] ?? '';
                    final String endTimeStr = data['endTime'] ?? '';
                    final String location = data['location'] ?? '';
                    final String description = data['description'] ?? '';
                    
                    if (title.isEmpty || startTimeStr.isEmpty || endTimeStr.isEmpty) {
                      print('⚠️ Calendar event missing required fields');
                      return;
                    }
                    
                    // Parse ISO 8601 dates
                    final startTime = DateTime.parse(startTimeStr);
                    final endTime = DateTime.parse(endTimeStr);
                    
                    print('📅 Adding calendar event: $title from $startTime to $endTime');
                    
                    // Create the event
                    await _addCalendarEvent(
                      title: title,
                      startTime: startTime,
                      endTime: endTime,
                      location: location,
                      description: description,
                    );
                    
                    // Refresh the calendar events list
                    await _initializeCalendar();
                    
                  } catch (e) {
                    print('⚠️ Error handling calendar event request: $e');
                  }
                },
              );
              
              // Add JavaScript handler for making phone calls
              controller.addJavaScriptHandler(
                handlerName: 'FlutterPhoneCall',
                callback: (args) async {
                  try {
                    final data = args[0];
                    final String phoneNumber = data['phoneNumber'] ?? '';
                    final String placeName = data['placeName'] ?? '';
                    
                    if (phoneNumber.isEmpty) {
                      print('⚠️ Phone call missing phone number');
                      return;
                    }
                    
                    print('📞 Initiating phone call to: $phoneNumber ($placeName)');
                    
                    // Launch phone dialer
                    await _makePhoneCall(phoneNumber, placeName);
                    
                  } catch (e) {
                    print('⚠️ Error handling phone call request: $e');
                  }
                },
              );
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final url = navigationAction.request.url;
              
              // Handle intent:// URLs (Android app launch intents)
              if (url != null && url.scheme == 'intent') {
                print('🗺️ Intercepted intent URL, preventing WebView navigation');
                // Don't load intent URLs in WebView, they'll be handled by the system
                return NavigationActionPolicy.CANCEL;
              }
              
              // Allow all other URLs
              return NavigationActionPolicy.ALLOW;
            },
            onLoadStart: (controller, url) {
              print('🌐 Page started loading: $url');
            },
            onLoadStop: (controller, url) async {
              print('🌐 Page finished loading: $url');
              _setupJavaScriptChannels();
            },
                  onConsoleMessage: (controller, consoleMessage) {
                    // Filter out Google Maps alpha channel warnings
                    final message = consoleMessage.message;
                    if (message.contains('alpha channel of the Google Maps JavaScript API') ||
                        message.contains('For development purposes only')) {
                      return; // Skip these informational messages
                    }
                    print('🌐 WebView Console: $message');
                  },
            onPermissionRequest: (controller, request) async {
              print('🔐 Permission request: ${request.resources}');
              // Automatically grant microphone and other permissions
              return PermissionResponse(
                resources: request.resources,
                action: PermissionResponseAction.GRANT,
              );
            },
            onReceivedError: (controller, request, error) {
              print('❌ WebView error: ${error.description}');
            },
          ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
