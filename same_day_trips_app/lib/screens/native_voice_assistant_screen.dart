import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/trip.dart';
import '../models/stop.dart';
import '../services/gemini_service.dart';

class NativeVoiceAssistantScreen extends StatefulWidget {
  final Trip trip;
  final List<Stop> stops;

  const NativeVoiceAssistantScreen({
    super.key,
    required this.trip,
    required this.stops,
  });

  @override
  State<NativeVoiceAssistantScreen> createState() => _NativeVoiceAssistantScreenState();
}

class _NativeVoiceAssistantScreenState extends State<NativeVoiceAssistantScreen> {
  final _geminiService = GeminiService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isListening = false;
  bool _isSpeaking = false;

  // Voice services
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  bool _speechEnabled = false;

  // Location
  Position? _currentLocation;
  bool _locationEnabled = false;

  // Google Maps
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  LatLng? _mapCenter;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _addWelcomeMessage();
  }

  Future<void> _initializeServices() async {
    // Initialize speech recognition
    _speechEnabled = await _speech.initialize();
    
    // Initialize text-to-speech
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    // Initialize location
    await _initializeLocation();

    setState(() {});
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
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      setState(() {
        _currentLocation = position;
        _locationEnabled = true;
        _mapCenter = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      print('Location error: $e');
    }
  }

  void _addWelcomeMessage() {
    _messages.add(ChatMessage(
      text: "Hi! I'm your trip assistant. I can help you find places to visit, get directions, and plan your day in ${widget.trip.city}. What would you like to know?",
      isUser: false,
      timestamp: DateTime.now(),
    ));
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    _addUserMessage(text);
    await _processMessage(text);
  }

  void _addUserMessage(String text) {
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
    });
    _scrollToBottom();
  }

  void _addAssistantMessage(String text) {
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: false,
        timestamp: DateTime.now(),
      ));
    });
    _scrollToBottom();
  }

  Future<void> _processMessage(String message) async {
    setState(() => _isLoading = true);

    try {
      final response = await _geminiService.askWithMapsGrounding(
        query: message,
        userLatitude: _currentLocation?.latitude,
        userLongitude: _currentLocation?.longitude,
        tripContext: widget.trip,
        stopsContext: widget.stops,
      );

      _addAssistantMessage(response.text);
      
      // Speak the response
      await _speakText(response.text);

      // Update map if there are locations
      if (response.locations.isNotEmpty) {
        _updateMapWithLocations(response.locations);
      }

    } catch (e) {
      _addAssistantMessage("Sorry, I encountered an error: ${e.toString()}");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _speakText(String text) async {
    if (_isSpeaking) return;
    
    setState(() => _isSpeaking = true);
    await _flutterTts.speak(text);
    
    // Wait for speech to complete
    _flutterTts.setCompletionHandler(() {
      setState(() => _isSpeaking = false);
    });
  }

  void _updateMapWithLocations(List<MapLocation> locations) {
    final markers = <Marker>{};
    
    for (int i = 0; i < locations.length; i++) {
      final location = locations[i];
      markers.add(Marker(
        markerId: MarkerId('location_$i'),
        position: LatLng(location.latitude, location.longitude),
        infoWindow: InfoWindow(title: location.name),
      ));
    }

    setState(() {
      _markers = markers;
      if (locations.isNotEmpty) {
        _mapCenter = LatLng(locations.first.latitude, locations.first.longitude);
      }
    });

    // Update map camera
    if (_mapController != null && locations.isNotEmpty) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          _getBoundsFromLocations(locations),
          100.0,
        ),
      );
    }
  }

  LatLngBounds _getBoundsFromLocations(List<MapLocation> locations) {
    double minLat = locations.first.latitude;
    double maxLat = locations.first.latitude;
    double minLng = locations.first.longitude;
    double maxLng = locations.first.longitude;

    for (final location in locations) {
      minLat = minLat < location.latitude ? minLat : location.latitude;
      maxLat = maxLat > location.latitude ? maxLat : location.latitude;
      minLng = minLng < location.longitude ? minLng : location.longitude;
      maxLng = maxLng > location.longitude ? maxLng : location.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Future<void> _startListening() async {
    if (!_speechEnabled) return;

    setState(() => _isListening = true);

    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          _messageController.text = result.recognizedWords;
          _sendMessage();
          setState(() => _isListening = false);
        }
      },
    );
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
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
            icon: Icon(_locationEnabled ? Icons.location_on : Icons.location_off),
            onPressed: _initializeLocation,
          ),
        ],
      ),
      body: Column(
        children: [
          // Map Section
          Expanded(
            flex: 2,
            child: _mapCenter != null
                ? GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _mapCenter!,
                      zoom: 12.0,
                    ),
                    markers: _markers,
                    onMapCreated: (GoogleMapController controller) {
                      _mapController = controller;
                    },
                  )
                : const Center(
                    child: CircularProgressIndicator(),
                  ),
          ),
          
          // Chat Section
          Expanded(
            flex: 3,
            child: Column(
              children: [
                // Messages
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return ChatBubble(message: message);
                    },
                  ),
                ),
                
                // Loading indicator
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Assistant is thinking...'),
                      ],
                    ),
                  ),
                
                // Input Section
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    border: Border(top: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: Row(
                    children: [
                      // Voice button
                      IconButton(
                        onPressed: _isListening ? _stopListening : _startListening,
                        icon: Icon(
                          _isListening ? Icons.mic : Icons.mic_none,
                          color: _isListening ? Colors.red : Colors.grey,
                        ),
                      ),
                      
                      // Text input
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            hintText: 'Ask me anything about your trip...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      
                      // Send button
                      IconButton(
                        onPressed: _sendMessage,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _speech.stop();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: message.isUser 
            ? MainAxisAlignment.end 
            : MainAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.purple,
              child: const Icon(Icons.assistant, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: message.isUser ? Colors.blue : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  color: message.isUser ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue,
              child: const Icon(Icons.person, size: 16, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }
}

class MapLocation {
  final String name;
  final double latitude;
  final double longitude;

  MapLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
  });
}

