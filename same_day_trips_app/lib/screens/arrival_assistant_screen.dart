import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/trip.dart';
import '../models/stop.dart';
import '../services/gemini_service.dart';
import '../theme/app_colors.dart';

class ArrivalAssistantScreen extends StatefulWidget {
  final Trip trip;
  final List<Stop> stops;

  const ArrivalAssistantScreen({
    super.key,
    required this.trip,
    required this.stops,
  });

  @override
  State<ArrivalAssistantScreen> createState() => _ArrivalAssistantScreenState();
}

class _ArrivalAssistantScreenState extends State<ArrivalAssistantScreen> {
  final _geminiService = GeminiService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  Position? _currentLocation;
  bool _locationEnabled = false;
  String _locationStatus = 'Checking location...';

  @override
  void initState() {
    super.initState();
    _addWelcomeMessage();
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationStatus = 'Location services disabled';
        });
        return;
      }

      // Request location permission
      var permission = await Permission.location.request();
      if (!permission.isGranted) {
        setState(() {
          _locationStatus = 'Location permission denied';
        });
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      setState(() {
        _currentLocation = position;
        _locationEnabled = true;
        _locationStatus = 'Location enabled';
      });

      // Update location periodically
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 50, // Update every 50 meters
        ),
      ).listen((Position position) {
        setState(() {
          _currentLocation = position;
        });
      });
    } catch (e) {
      setState(() {
        _locationStatus = 'Location unavailable';
      });
      print('⚠️ Location error: $e');
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _addWelcomeMessage() {
    setState(() {
      _messages.add(ChatMessage(
        text: '''Welcome to ${widget.trip.city}! 🎉

I'm your AI travel assistant. I can help you with:
• Finding restaurants and cafes
• Getting directions
• Discovering nearby places
• Planning your time between meetings

What would you like to know?''',
        isUser: false,
        timestamp: DateTime.now(),
      ));
    });
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final userMessage = ChatMessage(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
      _messageController.clear();
    });

    _scrollToBottom();

    try {
      // Use current GPS location if available
      final response = await _geminiService.askWithMapsGrounding(
        query: text,
        userLatitude: _currentLocation?.latitude,
        userLongitude: _currentLocation?.longitude,
        tripContext: widget.trip,
        stopsContext: widget.stops,
      );

      final aiMessage = ChatMessage(
        text: response.text,
        isUser: false,
        timestamp: DateTime.now(),
        places: response.places,
        hasMapData: response.hasMapData,
      );

      setState(() {
        _messages.add(aiMessage);
        _isLoading = false;
      });

      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          text: 'Sorry, I encountered an error. Please try again.',
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isLoading = false;
      });
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Arrival Assistant'),
            Text(
              '${widget.trip.city} - ${widget.trip.date}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF9C27B0),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Trip context banner
          Container(
            color: context.purpleTint,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.flight_land, color: const Color(0xFF9C27B0)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${widget.stops.length} stops planned • ${widget.trip.groundTime} available',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF9C27B0),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      _locationEnabled ? Icons.my_location : Icons.location_off,
                      size: 16,
                      color: _locationEnabled ? context.successColor : context.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _locationStatus,
                        style: TextStyle(
                          fontSize: 11,
                          color: _locationEnabled ? context.successColor : context.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Quick suggestions
          _buildQuickSuggestions(),

          // Chat messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _buildMessageBubble(_messages[index]);
              },
            ),
          ),

          // Loading indicator
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  const CircularProgressIndicator(strokeWidth: 2),
                  const SizedBox(width: 12),
                  Text(
                    'Thinking...',
                    style: TextStyle(color: context.textSecondary),
                  ),
                ],
              ),
            ),

          // Input field
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              boxShadow: [
                BoxShadow(
                  color: context.borderColor,
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Ask me anything...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: _sendMessage,
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: () => _sendMessage(_messageController.text),
                  backgroundColor: const Color(0xFF9C27B0),
                  mini: true,
                  child: const Icon(Icons.send, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickSuggestions() {
    final suggestions = [
      'Find lunch nearby',
      'Coffee shops',
      'Best route to next meeting',
      'Quiet place to work',
    ];

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: suggestions.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              label: Text(suggestions[index]),
              onPressed: () => _sendMessage(suggestions[index]),
              backgroundColor: context.purpleTint,
            ),
          );
        },
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: message.isUser ? const Color(0xFF9C27B0) : context.surfaceColor.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: message.isUser ? Colors.white : context.textPrimary,
              ),
            ),
            if (message.hasMapData)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.map,
                      size: 16,
                      color: message.isUser ? Colors.white70 : context.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Powered by Google Maps',
                      style: TextStyle(
                        fontSize: 10,
                        color: message.isUser ? Colors.white70 : context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            if (message.places.isNotEmpty)
              ...message.places.map((place) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: InkWell(
                      onTap: () {
                        // TODO: Open place in maps
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: message.isUser ? Colors.white : context.primaryColor,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              place.name,
                              style: TextStyle(
                                fontSize: 12,
                                color: message.isUser ? Colors.white : context.primaryColor,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final List<PlaceInfo> places;
  final bool hasMapData;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.places = const [],
    this.hasMapData = false,
  });
}
