import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/trip.dart';
import '../models/stop.dart';

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
  late final WebViewController _controller;
  Position? _currentLocation;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

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
        setState(() {
          _currentLocation = position;
        });
        _updateLocationInWebView(position);
      });
    } catch (e) {
      print('⚠️ Location error: $e');
    }
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
        ),
      )
      ..loadRequest(_buildWebViewUrl());
  }

  Uri _buildWebViewUrl() {
    // Build URL with trip context and location
    final params = <String, String>{
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

    // TODO: Update this URL to where your web app is served
    // For development: http://localhost:5173
    // For production: wherever you deploy the web app
    return Uri.parse('http://localhost:5173').replace(queryParameters: params);
  }

  void _updateLocationInWebView(Position position) {
    // Send location update to web app via JavaScript
    _controller.runJavaScript('''
      if (window.updateLocation) {
        window.updateLocation(${position.latitude}, ${position.longitude});
      }
    ''');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Assistant'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _controller.reload();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
