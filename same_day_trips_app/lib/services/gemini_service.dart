import 'package:dio/dio.dart';
import '../models/trip.dart';
import '../models/stop.dart';

/// Gemini AI service with Google Maps grounding via direct REST API
class GeminiService {
  static const String geminiApiBaseUrl = 'https://generativelanguage.googleapis.com/v1beta';
  static const String apiKey = 'YOUR_GOOGLE_AI_API_KEY'; // TODO: Replace with your key

  final Dio _dio = Dio(BaseOptions(
    baseUrl: geminiApiBaseUrl,
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
  ));

  /// Ask Gemini a question with Google Maps grounding
  Future<GeminiResponse> askWithMapsGrounding({
    required String query,
    double? userLatitude,
    double? userLongitude,
    Trip? tripContext,
    List<Stop>? stopsContext,
  }) async {
    try {
      print('🔵 Calling Gemini API with Maps grounding...');

      // Build context prompt
      String contextPrompt = query;

      if (tripContext != null) {
        String locationInfo = '';
        if (userLatitude != null && userLongitude != null) {
          locationInfo = '- Current Location: Lat $userLatitude, Long $userLongitude\n';
        }

        String tripInfo = '''
You are helping a business traveler on a same-day trip.

Trip Details:
- Destination: ${tripContext.city} (${tripContext.destination})
- Date: ${tripContext.date}
${locationInfo}- Outbound: ${tripContext.departOrigin} → ${tripContext.arriveDestination} (${tripContext.outboundFlight})
- Return: ${tripContext.departDestination} → ${tripContext.arriveOrigin} (${tripContext.returnFlight})
- Available ground time: ${tripContext.groundTime}
''';

        if (stopsContext != null && stopsContext.isNotEmpty) {
          String stopsInfo = '';
          for (int i = 0; i < stopsContext.length; i++) {
            stopsInfo += '${i + 1}. ${stopsContext[i].name} (${stopsContext[i].address}) - ${stopsContext[i].formatDuration()}\n';
          }
          contextPrompt = '''$tripInfo

Planned stops:
$stopsInfo

User question: $query

Provide helpful, location-specific recommendations based on their itinerary and current context.''';
        } else {
          contextPrompt = '''$tripInfo

User question: $query

Provide helpful, location-specific recommendations for their trip.''';
        }
      }

      // Build request body with Maps grounding
      final Map<String, dynamic> requestBody = {
        'contents': [
          {
            'parts': [
              {'text': contextPrompt}
            ]
          }
        ],
        'tools': [
          {
            'googleMaps': {} // Enable Google Maps grounding
          }
        ],
      };

      // Add location context if provided
      if (userLatitude != null && userLongitude != null) {
        requestBody['toolConfig'] = {
          'retrievalConfig': {
            'latLng': {
              'latitude': userLatitude,
              'longitude': userLongitude,
            }
          }
        };
      }

      // Call Gemini API
      final response = await _dio.post(
        '/models/gemini-2.0-flash-exp:generateContent?key=$apiKey',
        data: requestBody,
      );

      print('✅ Gemini API response received');

      final data = response.data;

      // Extract response text
      String responseText = 'No response received';
      if (data['candidates'] != null && data['candidates'].isNotEmpty) {
        final candidate = data['candidates'][0];
        if (candidate['content'] != null && candidate['content']['parts'] != null) {
          final parts = candidate['content']['parts'] as List;
          if (parts.isNotEmpty && parts[0]['text'] != null) {
            responseText = parts[0]['text'];
          }
        }
      }

      // Extract places from grounding metadata
      List<PlaceInfo> places = [];
      bool hasMapData = false;

      if (data['candidates'] != null && data['candidates'].isNotEmpty) {
        final candidate = data['candidates'][0];
        if (candidate['groundingMetadata'] != null) {
          hasMapData = true;
          final groundingMetadata = candidate['groundingMetadata'];

          if (groundingMetadata['groundingChunks'] != null) {
            for (var chunk in groundingMetadata['groundingChunks']) {
              if (chunk['maps'] != null) {
                places.add(PlaceInfo(
                  name: chunk['maps']['title'] ?? 'Unknown',
                  uri: chunk['maps']['uri'] ?? '',
                ));
              }
            }
          }
        }
      }

      return GeminiResponse(
        text: responseText,
        places: places,
        hasMapData: hasMapData,
      );
    } on DioException catch (e) {
      print('⚠️ Gemini API error: ${e.response?.data ?? e.message}');

      final errorMsg = e.response?.data?['error'] ?? e.message ?? 'Unknown error';

      return GeminiResponse(
        text: 'Sorry, I encountered an error: $errorMsg',
        places: [],
        hasMapData: false,
      );
    } catch (e) {
      print('⚠️ Unexpected error: $e');
      return GeminiResponse(
        text: 'Sorry, I encountered an unexpected error: ${e.toString()}',
        places: [],
        hasMapData: false,
      );
    }
  }

  /// Generate quick suggestions based on trip context
  Future<List<String>> getSuggestions({
    required Trip trip,
    List<Stop>? stops,
    double? userLatitude,
    double? userLongitude,
  }) async {
    // Default suggestions
    final defaultSuggestions = [
      'Find lunch near my next meeting',
      'Coffee shops nearby',
      'Where to park at ${trip.destination} airport?',
      'Best route to avoid traffic',
    ];

    return defaultSuggestions;
  }
}

/// Response from Gemini with Maps grounding
class GeminiResponse {
  final String text;
  final List<PlaceInfo> places;
  final bool hasMapData;

  GeminiResponse({
    required this.text,
    required this.places,
    required this.hasMapData,
  });
}

/// Information about a place from Google Maps
class PlaceInfo {
  final String name;
  final String uri;

  PlaceInfo({
    required this.name,
    required this.uri,
  });
}
