import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/user_profile_service.dart';
import '../theme/app_colors.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = UserProfileService();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _homeCtrl = TextEditingController();

  final List<String> _airlineOptions = ['AA', 'DL', 'UA', 'WN', 'AS', 'B6', 'NK', 'F9'];
  final List<String> _selectedAirlines = [];

  int _earliestDepart = 5;
  int _departBy = 9;
  int _returnAfter = 15;
  int _returnBy = 19;
  double _minGroundTime = 3.0;
  int _minDuration = 50;
  int _maxDuration = 204;
  bool _shareWithAssistant = false;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await _service.load();
    if (profile != null) {
      _nameCtrl.text = profile.name ?? '';
      _emailCtrl.text = profile.email ?? '';
      _phoneCtrl.text = profile.phone ?? '';
      _homeCtrl.text = profile.homeAirport ?? '';
      _selectedAirlines
        ..clear()
        ..addAll(profile.preferredAirlines);
      _earliestDepart = profile.earliestDepart ?? _earliestDepart;
      _departBy = profile.departBy ?? _departBy;
      _returnAfter = profile.returnAfter ?? _returnAfter;
      _returnBy = profile.returnBy ?? _returnBy;
      _minGroundTime = profile.minGroundTime ?? _minGroundTime;
      _minDuration = profile.minDuration ?? _minDuration;
      _maxDuration = profile.maxDuration ?? _maxDuration;
      _shareWithAssistant = profile.shareWithAssistant;
    }
    setState(() => _loading = false);
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = UserProfile(
      name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      homeAirport: _homeCtrl.text.trim().isEmpty ? null : _homeCtrl.text.trim().toUpperCase(),
      preferredAirlines: List<String>.from(_selectedAirlines),
      earliestDepart: _earliestDepart,
      departBy: _departBy,
      returnAfter: _returnAfter,
      returnBy: _returnBy,
      minGroundTime: _minGroundTime,
      minDuration: _minDuration,
      maxDuration: _maxDuration,
      shareWithAssistant: _shareWithAssistant,
    );
    await _service.save(profile);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Profile saved'),
          backgroundColor: context.successColor,
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.pop(context, profile);
    }
  }

  String _formatHours(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    if (m == 0) return '${h}h';
    return '${h}h ${m}min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Defaults'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveProfile,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Contact', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailCtrl,
                      decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneCtrl,
                      decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder()),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 24),
                    Text('Defaults', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _homeCtrl,
                      decoration: const InputDecoration(labelText: 'Home Airport (IATA)', border: OutlineInputBorder()),
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 3,
                      validator: (v) {
                        if (v == null || v.isEmpty) return null;
                        if (v.length != 3) return '3-letter code';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Text('Preferred Airlines', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _airlineOptions.map((code) {
                        final selected = _selectedAirlines.contains(code);
                        return FilterChip(
                          label: Text(code),
                          selected: selected,
                          onSelected: (val) {
                            setState(() {
                              if (val) {
                                _selectedAirlines.add(code);
                              } else {
                                _selectedAirlines.remove(code);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _earliestDepart,
                            decoration: const InputDecoration(labelText: 'Earliest Depart', border: OutlineInputBorder()),
                            items: List.generate(12, (i) => i + 5)
                                .map((h) => DropdownMenuItem(value: h, child: Text('${h}:00')))
                                .toList(),
                            onChanged: (v) => setState(() => _earliestDepart = v ?? _earliestDepart),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _departBy,
                            decoration: const InputDecoration(labelText: 'Latest Depart', border: OutlineInputBorder()),
                            items: List.generate(12, (i) => i + 5)
                                .map((h) => DropdownMenuItem(value: h, child: Text('${h}:00')))
                                .toList(),
                            onChanged: (v) => setState(() => _departBy = v ?? _departBy),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _returnAfter,
                            decoration: const InputDecoration(labelText: 'Earliest Home Arrival', border: OutlineInputBorder()),
                            items: List.generate(10, (i) => i + 14)
                                .map((h) => DropdownMenuItem(value: h, child: Text('${h}:00')))
                                .toList(),
                            onChanged: (v) => setState(() => _returnAfter = v ?? _returnAfter),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _returnBy,
                            decoration: const InputDecoration(labelText: 'Latest Home Arrival', border: OutlineInputBorder()),
                            items: List.generate(8, (i) => i + 17)
                                .map((h) => DropdownMenuItem(value: h, child: Text('${h}:00')))
                                .toList(),
                            onChanged: (v) => setState(() => _returnBy = v ?? _returnBy),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Minimum Meeting Time: ${_formatHours(_minGroundTime)}'),
                    Slider(
                      value: _minGroundTime,
                      min: 2,
                      max: 8,
                      divisions: 12,
                      label: _formatHours(_minGroundTime),
                      onChanged: (v) => setState(() => _minGroundTime = v),
                    ),
                    const SizedBox(height: 8),
                    Text('Minimum Flight Time: ${_formatHours(_minDuration / 60)} each way'),
                    Slider(
                      value: _minDuration.toDouble(),
                      min: 30,
                      max: 180,
                      divisions: 15,
                      label: _formatHours(_minDuration / 60),
                      onChanged: (v) {
                        setState(() {
                          _minDuration = v.toInt();
                          if (_maxDuration < _minDuration) {
                            _maxDuration = _minDuration;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Text('Maximum Flight Time: ${_formatHours(_maxDuration / 60)} each way'),
                    Slider(
                      value: _maxDuration.toDouble(),
                      min: _minDuration.toDouble(),
                      max: 300,
                      divisions: 24,
                      label: _formatHours(_maxDuration / 60),
                      onChanged: (v) => setState(() => _maxDuration = v.toInt()),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Share profile with assistant'),
                      value: _shareWithAssistant,
                      onChanged: (v) => setState(() => _shareWithAssistant = v),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saveProfile,
                        icon: const Icon(Icons.save),
                        label: const Text('Save'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(14),
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
