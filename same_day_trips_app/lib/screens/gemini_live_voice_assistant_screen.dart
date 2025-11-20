import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:gemini_live/gemini_live.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/trip.dart';
import '../models/stop.dart';

class GeminiLiveVoiceAssistantScreen extends StatefulWidget {
  final Trip trip;
  final List<Stop> stops;

  const GeminiLiveVoiceAssistantScreen({
    super.key,
    required this.trip,
    required this.stops,
  });

  @override
  State<GeminiLiveVoiceAssistantScreen> createState() => _GeminiLiveVoiceAssistantScreenState();
}

enum Role { user, model }

class ChatMessage {
  final String text;
  final Role author;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.author,
    required this.timestamp,
  });
}

enum ConnectionStatus { connecting, connected, disconnected }

class _GeminiLiveVoiceAssistantScreenState extends State<GeminiLiveVoiceAssistantScreen> {
  // --- Gemini Live API and Session Management ---
  late final GoogleGenAI _genAI;
  LiveSession? _session;
  final TextEditingController _textController = TextEditingController();

  // --- State Management Variables ---
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  bool _isReplying = false;
  final List<ChatMessage> _messages = [];
  ChatMessage? _streamingMessage;
  String _statusText = "Initializing connection...";

  // --- Audio Handling Variables ---
  StreamSubscription<RecordState>? _recordSub;
  bool _isRecording = false;
  final AudioRecorder _audioRecorder = AudioRecorder();

  // --- Map and Location ---
  Set<Marker> _markers = {};
  LatLng _mapCenter = const LatLng(35.2271, -80.8431); // Charlotte default
  double _mapZoom = 12.0;
  Position? _currentLocation;
  bool _locationPermissionGranted = false;

  /// Initializes the connection to the Gemini Live API when the widget is first created.
  Future<void> _initialize() async {
    await _connectToLiveAPI();
  }

  @override
  void initState() {
    super.initState();
    // Initialize the GoogleGenAI instance with the API key from environment.
    _genAI = GoogleGenAI(apiKey: dotenv.env['GEMINI_API_KEY'] ?? '');
    // Start the connection process.
    _initialize();
    // Subscribe to the audio recorder's state to update the UI.
    _recordSub = _audioRecorder.onStateChanged().listen((recordState) {
      if (mounted) {
        setState(() => _isRecording = recordState == RecordState.record);
      }
    });
    // Initialize location services
    _initializeLocation();
  }

  @override
  void dispose() {
    // Clean up resources to prevent memory leaks.
    _session?.close();
    _audioRecorder.dispose();
    _textController.dispose();
    _recordSub?.cancel();
    super.dispose();
  }

  /// A helper function to safely update the status text on the UI.
  void _updateStatus(String text) {
    if (mounted) setState(() => _statusText = text);
  }

  /// Initialize location services and request permissions
  Future<void> _initializeLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _updateStatus("Location services are disabled. Please enable them for better assistance.");
        return;
      }

      // Request location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _updateStatus("Location permission denied. Some features may be limited.");
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _updateStatus("Location permission permanently denied. Please enable in settings.");
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentLocation = position;
        _mapCenter = LatLng(position.latitude, position.longitude);
        _locationPermissionGranted = true;
      });

      // Add current location marker
      _markers.add(Marker(
        markerId: const MarkerId('current_location'),
        position: LatLng(position.latitude, position.longitude),
        infoWindow: const InfoWindow(title: 'Your Location'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      ));

      print('📍 Location initialized: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      print('Location error: $e');
      _updateStatus("Could not get location. Using default map center.");
    }
  }

  // --- Connection Management ---
  /// Establishes a WebSocket connection to the Gemini Live API.
  Future<void> _connectToLiveAPI() async {
    // Prevent multiple connection attempts if one is already in progress.
    if (_connectionStatus == ConnectionStatus.connecting) return;

    // Safely close any pre-existing session before creating a new one.
    await _session?.close();
    setState(() {
      _session = null;
      _connectionStatus = ConnectionStatus.connecting;
      _messages.clear(); // Clear previous chat history.
      // Add a temporary message to inform the user about the connection attempt.
      _addMessage(
        ChatMessage(
          text: "Connecting to Gemini Live API for your trip to ${widget.trip.city}...",
          author: Role.model,
          timestamp: DateTime.now(),
        ),
      );
      _updateStatus("Connecting to Gemini Live API...");
    });

    try {
      final modelName = 'gemini-2.0-flash-live-001';
      
      // Define the tools available to the model
      final tools = [
        Tool(
          functionDeclarations: [
            FunctionDeclaration(
              'add_stop',
              'Add a stop to the trip itinerary. Use this when the user wants to visit a place.',
              Schema(
                SchemaType.object,
                properties: {
                  'name': Schema(SchemaType.string, description: 'The name of the place to visit'),
                  'location': Schema(SchemaType.string, description: 'The address or city of the place'),
                  'duration': Schema(SchemaType.string, description: 'Estimated duration of the visit (e.g., "1 hour")'),
                },
                requiredProperties: ['name', 'location'],
              ),
            ),
          ],
        ),
      ];

      // Initiate the connection with specified parameters.
      final session = await _genAI.live.connect(
        LiveConnectParameters(
          // Specify the model to use.
          model: modelName,
          // Configure the generation output.
          config: GenerationConfig(
            // Define the expected response format (modality).
            responseModalities: [Modality.TEXT],
          ),
          tools: tools,
          // Provide system instructions to guide the model's behavior.
          systemInstruction: Content(
            parts: [
              Part(
                text: "You are a helpful AI travel assistant for a same-day trip to ${widget.trip.city}. "
                    "Trip Details: Destination: ${widget.trip.city}, Date: ${widget.trip.date}, "
                    "Outbound: ${widget.trip.outboundFlight}, Return: ${widget.trip.returnFlight}. "
                    "Current Stops: ${widget.stops.map((s) => s.name).join(', ')}. "
                    "User Location: ${_currentLocation != null ? '${_currentLocation!.latitude}, ${_currentLocation!.longitude}' : 'Unknown'}. "
                    "You can help find places, add stops to itinerary, get directions, or find nearby attractions. "
                    "When suggesting places, consider proximity to the user's current location. "
                    "Always provide comprehensive, detailed, and well-structured answers. "
                    "If the user wants to go somewhere, use the add_stop tool to add it to their plan.",
              ),
            ],
          ),
          // Define callbacks to handle WebSocket events.
          callbacks: LiveCallbacks(
            onOpen: () => _updateStatus("Connection successful! Try speaking or typing."),
            onMessage: _handleLiveAPIResponse, // Called when a message is received.
            onToolCall: _handleToolCall, // Handle tool calls
            onError: (error, stack) {
              print('🚨 Error occurred: $error');
              if (mounted) {
                setState(() => _connectionStatus = ConnectionStatus.disconnected);
              }
            },
            onClose: (code, reason) {
              print('🚪 Connection closed: $code, $reason');
              if (mounted) {
                setState(() => _connectionStatus = ConnectionStatus.disconnected);
              }
            },
          ),
        ),
      );

      // If the connection is successful, update the state.
      if (mounted) {
        setState(() {
          _session = session;
          _connectionStatus = ConnectionStatus.connected;
          _messages.removeLast(); // Remove the "Connecting..." message.
          // Add a welcome message.
          _addMessage(
            ChatMessage(
              text: "Hello! I'm your AI travel assistant for ${widget.trip.city}. "
                  "I can help you find places, add stops to your itinerary, or get directions. "
                  "Press the mic button to speak or type a message!",
              author: Role.model,
              timestamp: DateTime.now(),
            ),
          );
        });
      }
    } catch (e) {
      print("Connection failed: $e");
      if (mounted) {
        setState(() => _connectionStatus = ConnectionStatus.disconnected);
      }
    }
  }

  /// Handle tool calls from the model
  Future<void> _handleToolCall(LiveToolCall toolCall) async {
    print('🛠️ Tool call received: ${toolCall.functionCalls.map((f) => f.name).join(', ')}');
    
    final toolResponses = <FunctionResponse>[];

    for (final functionCall in toolCall.functionCalls) {
      if (functionCall.name == 'add_stop') {
        final args = functionCall.args;
        final name = args['name'] as String?;
        final location = args['location'] as String?;
        final duration = args['duration'] as String? ?? '1 hour';

        if (name != null && location != null) {
          // Execute the action
          await _addStop(name, location, duration);
          
          // Create success response
          toolResponses.add(FunctionResponse(
            name: functionCall.name,
            id: functionCall.id,
            response: {'result': 'Stop "$name" added to itinerary successfully.'},
          ));
        } else {
          // Create error response
          toolResponses.add(FunctionResponse(
            name: functionCall.name,
            id: functionCall.id,
            response: {'error': 'Missing name or location'},
          ));
        }
      }
    }

    // Send tool responses back to the model
    if (_session != null && toolResponses.isNotEmpty) {
      _session!.sendToolResponse(
        LiveClientToolResponse(
          toolResponses: toolResponses,
        ),
      );
    }
  }

  /// Add a stop to the local state
  Future<void> _addStop(String name, String location, String duration) async {
    setState(() {
      widget.stops.add(Stop(
        name: name,
        address: location,
        duration: duration,
        type: StopType.activity, // Default
        latitude: 0, // Placeholder
        longitude: 0, // Placeholder
      ));
      
      _addMessage(ChatMessage(
        text: "✅ Added stop: $name",
        author: Role.model,
        timestamp: DateTime.now(),
      ));
    });
    print("✅ Added stop: $name at $location");
  }

  // --- Message Handling ---
  /// Handles incoming messages from the Gemini Live API.
  void _handleLiveAPIResponse(LiveServerMessage message) {
    if (!mounted) return;

    final textChunk = message.text;
    print('📥 Received message textchunk: $textChunk');
    // If a text chunk is received, update the streaming message.
    if (textChunk != null) {
      setState(() {
        if (_streamingMessage == null) {
          // If this is the first chunk, create a new streaming message.
          _streamingMessage = ChatMessage(text: textChunk, author: Role.model, timestamp: DateTime.now());
        } else {
          // Otherwise, append the new chunk to the existing message text.
          _streamingMessage = ChatMessage(
            text: _streamingMessage!.text + textChunk,
            author: Role.model,
            timestamp: _streamingMessage!.timestamp,
          );
        }
      });
    }

    // When the model signals that its turn is complete, finalize the message.
    if (message.serverContent?.turnComplete ?? false) {
      setState(() {
        if (_streamingMessage != null) {
          // Move the completed streaming message into the main message list.
          _messages.add(_streamingMessage!);
          _streamingMessage = null; // Clear the streaming message.
        }
        _isReplying = false; // Allow the user to send another message.
      });
    }
  }

  /// A helper function to add a new message to the list and update the UI.
  void _addMessage(ChatMessage message) {
    if (!mounted) return;
    setState(() {
      _messages.add(message);
    });
  }

  // --- Audio Recording ---
  /// Toggles audio recording on and off.
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      // --- Stop Recording Logic ---
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false); // Update UI immediately.

      if (path != null) {
        print("Recording stopped. File path: $path");

        // 1. Read the recorded audio file as bytes.
        final file = File(path);
        final audioBytes = await file.readAsBytes();

        // 2. Display a message in the UI to confirm audio was sent.
        _addMessage(ChatMessage(text: "[User audio sent]", author: Role.user, timestamp: DateTime.now()));

        // 3. Send the audio data to the server.
        if (_session != null) {
          setState(() => _isReplying = true);

          _session!.sendMessage(
            LiveClientMessage(
              clientContent: LiveClientContent(
                turns: [
                  Content(
                    role: "user",
                    parts: [
                      Part(
                        // The 'inlineData' field is used for sending binary data like audio.
                        inlineData: Blob(
                          // The MIME type must match the audio format.
                          mimeType: 'audio/m4a',
                          // The binary data must be Base64 encoded.
                          data: base64Encode(audioBytes),
                        ),
                      ),
                    ],
                  ),
                ],
                turnComplete: true, // Signal that this is a complete user turn.
              ),
            ),
          );
        }
        // 4. Delete the temporary audio file to save space.
        await file.delete();
      }
    } else {
      // --- Start Recording Logic ---
      // Request microphone permission before starting.
      if (await Permission.microphone.request().isGranted) {
        final tempDir = await getTemporaryDirectory();
        // Use a file extension that matches the encoder. .m4a is for AAC.
        final filePath = '${tempDir.path}/temp_audio.m4a';

        // Start recording with a configuration that matches the MIME type.
        await _audioRecorder.start(
          RecordConfig(
            encoder: AudioEncoder.aacLc,
            sampleRate: 16000,
            bitRate: 128000,
          ),
          path: filePath,
        );
      } else {
        print("Microphone permission was denied.");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Microphone permission is required.")));
        }
      }
    }
  }

  /// Sends a text message to the API.
  Future<void> _sendMessage() async {
    final text = _textController.text;
    // Do not send if the input is empty, the model is replying, or the session is not active.
    if (text.isEmpty || _isReplying || _session == null) {
      return;
    }

    // Add the user's message to the UI immediately for a responsive feel.
    _addMessage(
      ChatMessage(text: text, author: Role.user, timestamp: DateTime.now()),
    );

    setState(() => _isReplying = true);

    // Send the message to the Gemini API.
    _session!.sendMessage(
      LiveClientMessage(
        clientContent: LiveClientContent(
          turns: [Content(role: "user", parts: [Part(text: text)])],
          turnComplete: true,
        ),
      ),
    );

    // Clear the input field after sending.
    _textController.clear();
  }

  /// Builds the text input composer with buttons for audio and sending.
  Widget _buildTextComposer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      color: Theme.of(context).cardColor,
      child: Row(
        children: [
          // Button to toggle audio recording.
          IconButton(
            icon: Icon(
              _isRecording ? Icons.stop_circle_outlined : Icons.mic_none_outlined,
            ),
            color: _isRecording ? Colors.red : Theme.of(context).iconTheme.color,
            onPressed: _toggleRecording,
          ),
          // The main text input field.
          Expanded(
            child: TextField(
              controller: _textController,
              onSubmitted: (_) => _sendMessage(),
              decoration: const InputDecoration.collapsed(
                hintText: 'Ask about places to visit or things to do...',
              ),
            ),
          ),
          // Button to send the message.
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _sendMessage,
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }

  /// Builds a chat message bubble.
  Widget _buildBubble(ChatMessage message) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: message.author == Role.user
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: message.author == Role.user
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(32.0),
              ),
              child: SelectableText(message.text),
            ),
          ),
        ],
      ),
    );
  }

  // --- UI Widget Builder ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemini Live Voice Assistant'),
        actions: [
          // Location refresh button
          IconButton(
            icon: Icon(
              _locationPermissionGranted ? Icons.my_location : Icons.location_disabled,
              color: _locationPermissionGranted ? Colors.blue : Colors.grey,
            ),
            onPressed: _initializeLocation,
            tooltip: 'Refresh Location',
          ),
          // A visual indicator for the connection status.
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Icon(
              Icons.circle,
              color: _connectionStatus == ConnectionStatus.connected
                  ? Colors.green
                  : _connectionStatus == ConnectionStatus.connecting
                  ? Colors.orange
                  : Colors.red,
              size: 16,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Map
          Expanded(
            flex: 2,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _mapCenter,
                zoom: _mapZoom,
              ),
              markers: _markers,
              onMapCreated: (GoogleMapController controller) {
                // Map controller is available
              },
            ),
          ),
          
          // Status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: Colors.grey[100],
            child: Text(
              _statusText,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),
          
          // Chat messages
          Expanded(
            flex: 3,
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              reverse: true, // Shows the latest messages at the bottom.
              // The item count includes the streaming message if it exists.
              itemCount: _messages.length + (_streamingMessage == null ? 0 : 1),
              itemBuilder: (context, index) {
                // If there's a streaming message, render it at the top (index 0).
                if (_streamingMessage != null && index == 0) {
                  return _buildBubble(_streamingMessage!);
                }
                // Adjust the index to access the main messages list.
                final messageIndex = index - (_streamingMessage == null ? 0 : 1);
                final message = _messages.reversed.toList()[messageIndex];
                return _buildBubble(message);
              },
            ),
          ),
          
          // Show a progress bar while the model is replying.
          if (_isReplying) const LinearProgressIndicator(),
          const Divider(height: 1.0),
          
          // If disconnected, show a button to reconnect.
          if (_connectionStatus == ConnectionStatus.disconnected)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text("Reconnect"),
                onPressed: _connectToLiveAPI,
              ),
            ),
          
          // If connected, show the message input composer.
          if (_connectionStatus == ConnectionStatus.connected)
            _buildTextComposer(),
        ],
      ),
    );
  }
}