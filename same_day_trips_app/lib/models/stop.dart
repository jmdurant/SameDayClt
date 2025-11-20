/// Represents a stop/meeting location on a same-day trip
class Stop {
  final String id;
  final String name;
  final String address;
  final int durationMinutes; // How long to spend at this stop
  final double? latitude;
  final double? longitude;
  final DateTime? startTime; // Optional scheduled start time (from calendar)

  Stop({
    required this.id,
    required this.name,
    required this.address,
    this.durationMinutes = 30,
    this.latitude,
    this.longitude,
    this.startTime,
  });

  Stop copyWith({
    String? id,
    String? name,
    String? address,
    int? durationMinutes,
    double? latitude,
    double? longitude,
    DateTime? startTime,
  }) {
    return Stop(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      startTime: startTime ?? this.startTime,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'durationMinutes': durationMinutes,
      'latitude': latitude,
      'longitude': longitude,
      'startTime': startTime?.toIso8601String(),
    };
  }

  factory Stop.fromJson(Map<String, dynamic> json) {
    return Stop(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String,
      durationMinutes: json['durationMinutes'] as int? ?? 30,
      latitude: json['latitude'] as double?,
      longitude: json['longitude'] as double?,
      startTime: json['startTime'] != null ? DateTime.tryParse(json['startTime']) : null,
    );
  }

  String formatDuration() {
    if (durationMinutes < 60) {
      return '$durationMinutes min';
    }
    final hours = durationMinutes ~/ 60;
    final mins = durationMinutes % 60;
    if (mins == 0) {
      return '${hours}h';
    }
    return '${hours}h ${mins}m';
  }

  String? formatStartTime() {
    if (startTime == null) return null;
    final hour = startTime!.hour % 12 == 0 ? 12 : startTime!.hour % 12;
    final minute = startTime!.minute.toString().padLeft(2, '0');
    final meridian = startTime!.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $meridian';
  }

  @override
  String toString() {
    return 'Stop(name: $name, address: $address, duration: ${formatDuration()})';
  }
}
