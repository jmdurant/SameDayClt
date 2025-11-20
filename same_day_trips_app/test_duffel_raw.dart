import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:dio/dio.dart';
import 'dart:convert';

/// Test script to see raw Duffel API response
Future<void> main() async {
  // Load environment variables
  await dotenv.load(fileName: "same_day_trips_app/.env");

  print('🧪 Testing Duffel API - Raw Response\n');

  final duffelToken = dotenv.env['DUFFEL_ACCESS_TOKEN'];
  print('Token: ${duffelToken?.substring(0, 20)}...\n');

  try {
    final dio = Dio();

    // Make a round-trip search request (CLT → ATL, same day)
    final requestBody = {
      'data': {
        'slices': [
          {
            'origin': 'CLT',
            'destination': 'ATL',
            'departure_date': '2025-11-21',
            'departure_time': {
              'from': '05:00',
              'to': '09:00',
            },
          },
          {
            'origin': 'ATL', // Return flight
            'destination': 'CLT',
            'departure_date': '2025-11-21',
            'departure_time': {
              'from': '15:00',
              'to': '19:00',
            },
          },
        ],
        'passengers': [
          {'type': 'adult'},
        ],
        'cabin_class': 'economy',
        'max_connections': 1,
        'return_offers': true,
      },
    };

    print('📤 Request body:');
    print(JsonEncoder.withIndent('  ').convert(requestBody));
    print('\n⏳ Calling Duffel API...\n');

    final response = await dio.post(
      'https://api.duffel.com/air/offer_requests',
      options: Options(headers: {
        'Authorization': 'Bearer $duffelToken',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Duffel-Version': 'v2',
      }),
      data: requestBody,
    );

    print('✅ Success! Response status: ${response.statusCode}\n');

    final data = response.data;
    final offers = data['data']?['offers'] as List? ?? [];

    print('📦 Found ${offers.length} offers\n');

    if (offers.isNotEmpty) {
      final firstOffer = offers[0] as Map<String, dynamic>;
      final slices = firstOffer['slices'] as List;

      print('🔍 FIRST OFFER DETAILS:');
      print('  Total price: \$${firstOffer['total_amount']}');
      print('  Number of slices: ${slices.length}\n');

      for (var i = 0; i < slices.length; i++) {
        final slice = slices[i] as Map<String, dynamic>;
        final segments = slice['segments'] as List;

        print('  ✈️ SLICE $i: ${slice['origin']} → ${slice['destination']}');
        print('     Duration: ${slice['duration']}');
        print('     Segments: ${segments.length}\n');

        for (var j = 0; j < segments.length; j++) {
          final seg = segments[j] as Map<String, dynamic>;
          print('     Segment $j:');
          print('       Departing at: ${seg['departing_at']}');
          print('       Arriving at: ${seg['arriving_at']}');
          print('       Flight: ${seg['marketing_carrier']?['iata_code']}${seg['marketing_carrier_flight_number']}');
          print('');
        }
      }

      print('\n🎯 KEY FINDING:');
      print('  Slice 0 (outbound CLT→ATL):');
      final outbound = slices[0] as Map<String, dynamic>;
      final outboundSegs = outbound['segments'] as List;
      print('    First segment departing_at: ${outboundSegs[0]['departing_at']}');

      print('\n  Slice 1 (return ATL→CLT):');
      final returnSlice = slices[1] as Map<String, dynamic>;
      final returnSegs = returnSlice['segments'] as List;
      print('    First segment departing_at: ${returnSegs[0]['departing_at']}');
      print('    Last segment arriving_at: ${returnSegs[returnSegs.length - 1]['arriving_at']}');
    }

  } catch (e, stack) {
    print('❌ Error: $e');
    print('Stack: $stack');
  }
}
