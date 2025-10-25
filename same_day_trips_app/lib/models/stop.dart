/// Represents a stop/meeting location on a same-day trip
class Stop {
  final String id;
  final String name;
  final String address;
  final int durationMinutes; // How long to spend at this stop
  final double? latitude;
  final double? longitude;

  Stop({
    required this.id,
    required this.name,
    required this.address,
    this.durationMinutes = 30,
    this.latitude,
    this.longitude,
  });

  Stop copyWith({
    String? id,
    String? name,
    String? address,
    int? durationMinutes,
    double? latitude,
    double? longitude,
  }) {
    return Stop(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
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

  @override
  String toString() {
    return 'Stop(name: $name, address: $address, duration: ${formatDuration()})';
  }
}
