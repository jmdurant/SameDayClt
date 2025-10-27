# Gemini Extension API Guide

## Overview

The Gemini Extension API allows your app to expose functions (tools) that Gemini can call during conversations. This enables Gemini to interact with your app's functionality - like searching for trips, adding stops, or fetching data.

## How It Works

1. **Register Functions**: Define functions that Gemini can call
2. **Handle Function Calls**: When Gemini requests to call a function, execute it
3. **Return Results**: Send the results back to Gemini for final response

## Function Calling in Gemini API

The Gemini API uses a `tools` parameter to define available functions. Here's the structure:

```json
{
  "tools": [
    {
      "function_declarations": [
        {
          "name": "search_trips",
          "description": "Search for same-day trips from Charlotte",
          "parameters": {
            "type": "object",
            "properties": {
              "destination": {
                "type": "string",
                "description": "The destination airport code (e.g., ATL, JFK)"
              },
              "date": {
                "type": "string",
                "description": "Date in YYYY-MM-DD format"
              }
            },
            "required": ["destination"]
          }
        }
      ]
    }
  ]
}
```

## Example Implementation for Same-Day Trips App

### 1. Define Trip Functions

Create functions that Gemini can call:

```dart
// In gemini_service.dart

/// Add custom function declarations to Gemini requests
Map<String, dynamic> addTripFunctions() {
  return {
    'tools': [
      {
        'function_declarations': [
          {
            'name': 'search_same_day_trips',
            'description': 'Search for same-day trips from Charlotte to various destinations. Returns flights, pricing, and itinerary information.',
            'parameters': {
              'type': 'object',
              'properties': {
                'destination': {
                  'type': 'string',
                  'description': 'Destination airport code or city name (e.g., "ATL", "Atlanta", "JFK")'
                },
                'date': {
                  'type': 'string',
                  'description': 'Travel date in YYYY-MM-DD format (optional, defaults to today)'
                }
              },
              'required': []
            }
          },
          {
            'name': 'add_stop_to_itinerary',
            'description': 'Add a stop/activity to the current trip itinerary',
            'parameters': {
              'type': 'object',
              'properties': {
                'name': {
                  'type': 'string',
                  'description': 'Name of the stop/place'
                },
                'address': {
                  'type': 'string',
                  'description': 'Full address of the stop'
                },
                'latitude': {
                  'type': 'number',
                  'description': 'Latitude coordinate'
                },
                'longitude': {
                  'type': 'number',
                  'description': 'Longitude coordinate'
                },
                'duration': {
                  'type': 'number',
                  'description': 'Duration in minutes (e.g., 60 for 1 hour)'
                }
              },
              'required': ['name', 'address']
            }
          },
          {
            'name': 'get_nearby_places',
            'description': 'Find nearby places (restaurants, coffee shops, attractions) based on current location',
            'parameters': {
              'type': 'object',
              'properties': {
                'category': {
                  'type': 'string',
                  'description': 'Type of place: restaurant, coffee_shop, attraction, parking, etc.',
                  'enum': ['restaurant', 'coffee_shop', 'attraction', 'parking', 'hotel']
                },
                'latitude': {
                  'type': 'number',
                  'description': 'Current latitude'
                },
                'longitude': {
                  'type': 'number',
                  'description': 'Current longitude'
                },
                'radius': {
                  'type': 'number',
                  'description': 'Search radius in meters (default: 5000m = 5km)'
                }
              },
              'required': ['category', 'latitude', 'longitude']
            }
          }
        ]
      }
    ]
  };
}
```

### 2. Handle Function Calls

When Gemini calls a function, it returns a response with `function_calls`:

```dart
/// Handle function calls from Gemini
Future<Map<String, dynamic>> handleFunctionCall({
  required Map<String, dynamic> functionCall,
  required Map<String, dynamic> context,
}) async {
  final functionName = functionCall['name'] as String;
  final arguments = functionCall['args'] as Map<String, dynamic>?;

  switch (functionName) {
    case 'search_same_day_trips':
      return await _executeSearchTrips(arguments, context);
    
    case 'add_stop_to_itinerary':
      return await _executeAddStop(arguments, context);
    
    case 'get_nearby_places':
      return await _executeNearbyPlaces(arguments, context);
    
    default:
      return {'error': 'Unknown function: $functionName'};
  }
}

Future<Map<String, dynamic>> _executeSearchTrips(
  Map<String, dynamic>? args,
  Map<String, dynamic> context,
) async {
  // Use your existing TripSearchService
  final searchService = TripSearchService();
  
  // Parse arguments
  final destination = args?['destination'] as String? ?? '';
  final date = args?['date'] as String? ?? DateTime.now().toIso8601String().split('T')[0];
  
  // Perform search
  final trips = await searchService.searchTrips(
    destination: destination,
    date: date,
    // ... other criteria
  );
  
  // Return results for Gemini
  return {
    'status': 'success',
    'trips_found': trips.length,
    'results': trips.map((trip) => {
      'destination': trip.city,
      'outbound': trip.outboundFlight,
      'return': trip.returnFlight,
      'total_price': trip.totalPrice,
      'ground_time': trip.groundTime,
      'available': trip.available,
    }).toList(),
  };
}

Future<Map<String, dynamic>> _executeAddStop(
  Map<String, dynamic>? args,
  Map<String, dynamic> context,
) async {
  // Add stop to current trip
  final name = args?['name'] as String? ?? '';
  final address = args?['address'] as String? ?? '';
  final latitude = args?['latitude'] as double?;
  final longitude = args?['longitude'] as double?;
  final duration = args?['duration'] as int? ?? 60;
  
  // Create and save stop
  // This would integrate with your existing Stop model
  
  return {
    'status': 'success',
    'stop_added': name,
    'message': 'Stop added to itinerary successfully',
  };
}

Future<Map<String, dynamic>> _executeNearbyPlaces(
  Map<String, dynamic>? args,
  Map<String, dynamic> context,
) async {
  // Use Gemini's Maps grounding or Mapbox service
  final category = args?['category'] as String? ?? 'restaurant';
  final latitude = args?['latitude'] as double?;
  final longitude = args?['longitude'] as double?;
  final radius = args?['radius'] as int? ?? 5000;
  
  // Search for nearby places using Gemini Maps grounding
  final response = await askWithMapsGrounding(
    query: 'Find nearby $category',
    userLatitude: latitude,
    userLongitude: longitude,
  );
  
  return {
    'status': 'success',
    'places': response.places,
  };
}
```

### 3. Function Calling Flow

Here's how the interaction works:

```dart
/// Complete flow for Gemini with function calling
Future<String> chatWithFunctions({
  required String userMessage,
  required List<Map<String, dynamic>> conversationHistory,
}) async {
  // Add function declarations to request
  final requestBody = {
    'contents': conversationHistory,
    ...addTripFunctions(), // Add function declarations
  };
  
  // Call Gemini
  final response = await _dio.post(
    '/models/gemini-2.5-flash:generateContent?key=$apiKey',
    data: requestBody,
  );
  
  // Check if Gemini wants to call a function
  final functionCalls = response.data['candidates']?[0]?['content']?['parts']
      ?.where((part) => part['function_call'] != null)
      .toList();
  
  if (functionCalls != null && functionCalls.isNotEmpty) {
    // Execute each function call
    final List<Map<String, dynamic>> functionResponses = [];
    
    for (var functionCall in functionCalls) {
      final functionCallData = functionCall['function_call'];
      final result = await handleFunctionCall(
        functionCall: functionCallData,
        context: conversationHistory.last,
      );
      
      functionResponses.add({
        'function_response': {
          'name': functionCallData['name'],
          'response': result,
        }
      });
    }
    
    // Send function results back to Gemini
    final followUpRequest = {
      'contents': [
        ...conversationHistory,
        {
          'role': 'model',
          'parts': response.data['candidates']?[0]?['content']?['parts'],
        },
        ...functionResponses,
      ],
      ...addTripFunctions(),
    };
    
    // Get final response
    final finalResponse = await _dio.post(
      '/models/gemini-2.5-flash:generateContent?key=$apiKey',
      data: followUpRequest,
    );
    
    return extractText(finalResponse.data);
  }
  
  // No function calls, return normal response
  return extractText(response.data);
}
```

## Integration with Voice Assistant

For your Gemini Live voice assistant, you can add function calling like this:

```dart
// In gemini_live_voice_assistant_screen.dart

// When connecting to Live API, provide function declarations
_session = await _genAI.live.connect(
  LiveConnectParameters(
    model: 'gemini-2.0-flash-live-001',
    tools: [
      // Define your functions here
      FunctionDeclaration(
        name: 'search_same_day_trips',
        description: 'Search for same-day trips',
        parameters: {
          'type': 'object',
          'properties': {
            'destination': {'type': 'string'},
            'date': {'type': 'string'},
          },
        },
      ),
      // ... more functions
    ],
    callbacks: LiveCallbacks(
      onToolCall: (toolCall) async {
        // Handle function calls
        final result = await handleFunctionCall(
          functionCall: toolCall,
          context: _messages.last,
        );
        // Send result back to Gemini
        await _session?.sendToolResponse({
          'function_responses': [result],
        });
      },
      // ... other callbacks
    ),
  ),
);
```

## Benefits

1. **Smart Interactions**: Gemini can search for trips, add stops, or fetch data automatically
2. **Natural Language**: Users can say "find me trips to Atlanta" and Gemini will call the right function
3. **Context Aware**: Gemini remembers the conversation and can make intelligent decisions
4. **Seamless UX**: Functions execute in the background, users get natural responses

## Next Steps

1. Implement function declarations in `gemini_service.dart`
2. Add function call handling logic
3. Integrate with existing services (TripSearchService, MapboxService)
4. Test with various user queries
5. Add more functions as needed (weather, directions, etc.)

## References

- [Gemini API Documentation](https://ai.google.dev/docs)
- [Function Calling Guide](https://ai.google.dev/docs/function_calling)
- Your existing code: `itinerary-planner.ts` (web voice assistant)

