import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:dio/dio.dart';

Future<void> main() async {
  // Load environment variables
  await dotenv.load(fileName: "same_day_trips_app/.env");

  print('🔑 Testing API Keys...\n');

  // Test Amadeus
  print('1️⃣ Testing Amadeus API...');
  final amadeusId = dotenv.env['AMADEUS_CLIENT_ID'];
  final amadeusSecret = dotenv.env['AMADEUS_CLIENT_SECRET'];
  print('   Client ID: ${amadeusId?.substring(0, 10)}...');

  try {
    final dio = Dio();
    final response = await dio.post(
      'https://api.amadeus.com/v1/security/oauth2/token',
      data: {
        'grant_type': 'client_credentials',
        'client_id': amadeusId,
        'client_secret': amadeusSecret,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    print('   ✅ Amadeus authenticated successfully!');
    print('   Access token: ${response.data['access_token'].toString().substring(0, 20)}...\n');
  } catch (e) {
    print('   ❌ Amadeus failed: $e\n');
  }

  // Test Duffel
  print('2️⃣ Testing Duffel API...');
  final duffelToken = dotenv.env['DUFFEL_ACCESS_TOKEN'];
  print('   Token: ${duffelToken?.substring(0, 20)}...');

  try {
    final dio = Dio();
    final response = await dio.get(
      'https://api.duffel.com/identity/whoami',
      options: Options(headers: {
        'Authorization': 'Bearer $duffelToken',
        'Accept': 'application/json',
        'Duffel-Version': 'v2',
      }),
    );
    print('   ✅ Duffel authenticated successfully!');
    print('   Account: ${response.data['data']['name']}\n');
  } catch (e) {
    print('   ❌ Duffel failed: $e\n');
  }

  // Test Gemini
  print('3️⃣ Testing Gemini API...');
  final geminiKey = dotenv.env['GEMINI_API_KEY'];
  print('   API Key: ${geminiKey?.substring(0, 20)}...');

  try {
    final dio = Dio();
    final response = await dio.get(
      'https://generativelanguage.googleapis.com/v1beta/models?key=$geminiKey',
    );
    print('   ✅ Gemini API working!');
    print('   Models available: ${response.data['models']?.length}\n');
  } catch (e) {
    print('   ❌ Gemini failed: $e\n');
  }

  // Test Mapbox
  print('4️⃣ Testing Mapbox API...');
  final mapboxToken = dotenv.env['MAPBOX_ACCESS_TOKEN'];
  print('   Token: ${mapboxToken?.substring(0, 20)}...');

  try {
    final dio = Dio();
    final response = await dio.get(
      'https://api.mapbox.com/geocoding/v5/mapbox.places/Charlotte.json?access_token=$mapboxToken',
    );
    print('   ✅ Mapbox working!');
    print('   Found: ${response.data['features']?.length} results\n');
  } catch (e) {
    print('   ❌ Mapbox failed: $e\n');
  }

  print('\n✅ All API tests complete!');
}
