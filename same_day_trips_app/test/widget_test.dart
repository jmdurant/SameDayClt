import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:same_day_trips_app/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SameDayTripsApp());

    // Verify that the app title is present
    expect(find.text('Same-Day Business Trips'), findsOneWidget);

    // Verify that the search screen loads
    expect(find.text('Plan Your Day Trip'), findsOneWidget);
  });
}
