import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import 'results_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();

  // Form values
  String _origin = 'CLT';
  DateTime _selectedDate = DateTime.now();
  int _departBy = 9; // 9 AM - realistic for commercial flights
  int _returnAfter = 15;
  int _returnBy = 19;
  double _minGroundTime = 3.0;
  int _maxDuration = 204; // ~3.4 hours flight time
  final List<String> _selectedDestinations = [];

  bool _isSearching = false;


  Future<void> _searchTrips() async {
    if (!_formKey.currentState!.validate()) return;

    print('🔍 Starting search...');
    print('  Origin: $_origin');
    print('  Date: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}');
    print('  Depart by: $_departBy:00');
    print('  Return window: $_returnAfter:00 - $_returnBy:00');
    print('  Min ground time: $_minGroundTime hrs');
    print('  Max duration: $_maxDuration min');

    setState(() => _isSearching = true);

    try {
      print('📡 Calling API...');
      final trips = await _apiService.searchTrips(
        origin: _origin,
        date: DateFormat('yyyy-MM-dd').format(_selectedDate),
        departBy: _departBy,
        returnAfter: _returnAfter,
        returnBy: _returnBy,
        minGroundTime: _minGroundTime,
        maxDuration: _maxDuration,
        destinations: _selectedDestinations.isEmpty ? null : _selectedDestinations,
      );

      print('✅ API returned ${trips.length} trips');

      if (!mounted) return;

      print('📱 Navigating to results screen...');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ResultsScreen(
            trips: trips,
            searchParams: {
              'origin': _origin,
              'date': DateFormat('MMM d, yyyy').format(_selectedDate),
              'departBy': _departBy,
              'returnBy': _returnBy,
            },
          ),
        ),
      );
    } catch (e) {
      print('❌ Search failed: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Search failed: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Same-Day Business Trips'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Icon(Icons.flight_takeoff, size: 48, color: Colors.blue),
                      const SizedBox(height: 8),
                      Text(
                        'Plan Your Day Trip',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Meet clients in person and still be home for dinner',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Origin Airport
              TextFormField(
                initialValue: _origin,
                decoration: const InputDecoration(
                  labelText: 'Your Home Airport',
                  hintText: 'e.g., CLT, ATL, LAX',
                  prefixIcon: Icon(Icons.home),
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.characters,
                maxLength: 3,
                onChanged: (value) => _origin = value.toUpperCase(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your airport code';
                  }
                  if (value.length != 3) {
                    return 'Airport code must be 3 letters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Date Picker
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = picked);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Travel Date',
                    prefixIcon: Icon(Icons.calendar_today),
                    border: OutlineInputBorder(),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(DateFormat('EEEE, MMM d, yyyy').format(_selectedDate)),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Time Preferences
              Text(
                'Travel Schedule',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),

              // Depart By
              DropdownButtonFormField<int>(
                initialValue: _departBy,
                decoration: const InputDecoration(
                  labelText: 'Latest Departure from Home',
                  helperText: 'When you want to leave your home airport',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.flight_takeoff),
                ),
                items: List.generate(12, (i) => i + 5)
                    .map((hour) => DropdownMenuItem(
                          value: hour,
                          child: Text('${hour}:00 AM'),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _departBy = value!),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _returnAfter,
                      decoration: const InputDecoration(
                        labelText: 'Earliest Home Arrival',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.flight_land),
                      ),
                      items: List.generate(10, (i) => i + 14)
                          .map((hour) => DropdownMenuItem(
                                value: hour,
                                child: Text('${hour > 12 ? hour - 12 : hour}:00 ${hour >= 12 ? 'PM' : 'AM'}'),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() => _returnAfter = value!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _returnBy,
                      decoration: const InputDecoration(
                        labelText: 'Latest Home Arrival',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.home),
                      ),
                      items: List.generate(8, (i) => i + 17)
                          .map((hour) => DropdownMenuItem(
                                value: hour,
                                child: Text('${hour > 12 ? hour - 12 : hour}:00 ${hour >= 12 ? 'PM' : 'AM'}'),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() => _returnBy = value!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Ground Time
              Text(
                'Minimum Meeting Time: ${_minGroundTime.toStringAsFixed(1)} hours',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                value: _minGroundTime,
                min: 2.0,
                max: 8.0,
                divisions: 12,
                label: '${_minGroundTime.toStringAsFixed(1)} hrs',
                onChanged: (value) => setState(() => _minGroundTime = value),
              ),
              const SizedBox(height: 16),

              // Max Flight Duration
              Text(
                'Maximum Flight Time: ${(_maxDuration / 60).toStringAsFixed(1)} hours each way',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                value: _maxDuration.toDouble(),
                min: 60,
                max: 300,
                divisions: 24,
                label: '${(_maxDuration / 60).toStringAsFixed(1)} hrs',
                onChanged: (value) => setState(() => _maxDuration = value.toInt()),
              ),
              const SizedBox(height: 24),

              // Search Button
              ElevatedButton.icon(
                onPressed: _isSearching ? null : _searchTrips,
                icon: _isSearching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_isSearching ? 'Searching...' : 'Find Trips'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(height: 16),

              // Info Card
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Search may take 30-60 seconds as we check real-time flight availability',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
