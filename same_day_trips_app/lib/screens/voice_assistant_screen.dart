import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_calendar/device_calendar.dart';
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

class _VoiceAssistantScreenState extends State<VoiceAssistantScreen> {
  InAppWebViewController? _controller;
  Position? _currentLocation;
  bool _isLoading = true;
  List<Event> _todaysEvents = [];

  Timer? _proactiveCheckTimer;

  @override
  void initState() {
    super.initState();
    // Enable landscape orientation for better Android Auto experience
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initializeWebView();
    _initializeLocationAndCalendar();
    _startProactiveChecks();
  }
  
  Future<void> _initializeLocationAndCalendar() async {
    // Initialize location first, then send to WebView
    await _initializeLocation();
    await _initializeCalendar();
    
    // After both are loaded, send initial data to WebView
    Future.delayed(const Duration(seconds: 2), () {
      if (_currentLocation != null) {
        print('📍 Sending initial location to WebView: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');
        _updateLocationInWebView(_currentLocation!);
      }
      if (_todaysEvents.isNotEmpty) {
        print('📅 Sending initial calendar to WebView');
        _updateCalendarInWebView();
      }
    });
  }

  @override
  void dispose() {
    _proactiveCheckTimer?.cancel();
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

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      print('📍 Got location: ${position.latitude}, ${position.longitude}');
      setState(() {
        _currentLocation = position;
      });

      // Update location periodically
      Geolocator.getPositionStream(
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

  void _initializeWebView() {
    // InAppWebView initialization happens in the build method
    print('🌐 Preparing InAppWebView...');
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
      params['lat'] = _currentLocation!.latitude.toString();
      params['lng'] = _currentLocation!.longitude.toString();
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
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
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
