import 'package:flutter/material.dart';
import 'screens/search_screen.dart';

void main() {
  runApp(const SameDayTripsApp());
}

class SameDayTripsApp extends StatelessWidget {
  const SameDayTripsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Same-Day Trips Finder',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const SearchScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
