import 'package:dio/dio.dart';
import '../models/trip.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:5000/api';
  // TODO: Set your Apify token via environment variable or secure config
  static const String APIFY_TOKEN = 'YOUR_APIFY_TOKEN_HERE';

  final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 300),
    receiveTimeout: const Duration(seconds: 300),
  ));

  Future<List<Trip>> searchTrips({
    required String origin,
    required String date,
    required int departBy,
    required int returnAfter,
    required int returnBy,
    required double minGroundTime,
    required int maxDuration,
    List<String>? destinations,
  }) async {
    try {
      final response = await _dio.post('/search', data: {
        'origin': origin,
        'date': date,
        'departBy': departBy,
        'returnAfter': returnAfter,
        'returnBy': returnBy,
        'minGroundTime': minGroundTime,
        'maxDuration': maxDuration,
        'destinations': destinations,
      });

      if (response.data['success'] == true) {
        final List<dynamic> tripsJson = response.data['trips'];
        return tripsJson.map((json) => Trip.fromJson(json)).toList();
      } else {
        throw Exception('Search failed: ${response.data['error']}');
      }
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  Future<double?> checkTuroPrice({
    required String city,
    required String pickupDatetime,
    required String returnDatetime,
  }) async {
    try {
      final response = await _dio.post('/check-turo', data: {
        'city': city,
        'pickupDatetime': pickupDatetime,
        'returnDatetime': returnDatetime,
        'apifyToken': APIFY_TOKEN,
      });

      if (response.data['success'] == true) {
        return response.data['price']?.toDouble();
      }
      return null;
    } catch (e) {
      print('Turo check error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> checkRewards({
    required String origin,
    required String destination,
    required String date,
    required String departTime,
  }) async {
    try {
      final response = await _dio.post('/check-rewards', data: {
        'origin': origin,
        'destination': destination,
        'date': date,
        'departTime': departTime,
      });

      if (response.data['success'] == true) {
        return response.data;
      }
      return null;
    } catch (e) {
      print('Rewards check error: $e');
      return null;
    }
  }
}
