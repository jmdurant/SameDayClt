class UserProfile {
  final String? name;
  final String? email;
  final String? phone;
  final String? homeAirport;
  final List<String> preferredAirlines;
  final int? earliestDepart;
  final int? departBy;
  final int? returnAfter;
  final int? returnBy;
  final double? minGroundTime;
  final int? minDuration;
  final int? maxDuration;
  final bool shareWithAssistant;

  const UserProfile({
    this.name,
    this.email,
    this.phone,
    this.homeAirport,
    this.preferredAirlines = const [],
    this.earliestDepart,
    this.departBy,
    this.returnAfter,
    this.returnBy,
    this.minGroundTime,
    this.minDuration,
    this.maxDuration,
    this.shareWithAssistant = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'phone': phone,
        'homeAirport': homeAirport,
        'preferredAirlines': preferredAirlines,
        'earliestDepart': earliestDepart,
        'departBy': departBy,
        'returnAfter': returnAfter,
        'returnBy': returnBy,
        'minGroundTime': minGroundTime,
        'minDuration': minDuration,
        'maxDuration': maxDuration,
        'shareWithAssistant': shareWithAssistant,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: json['name'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      homeAirport: json['homeAirport'] as String?,
      preferredAirlines: (json['preferredAirlines'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      earliestDepart: json['earliestDepart'] as int?,
      departBy: json['departBy'] as int?,
      returnAfter: json['returnAfter'] as int?,
      returnBy: json['returnBy'] as int?,
      minGroundTime: (json['minGroundTime'] as num?)?.toDouble(),
      minDuration: json['minDuration'] as int?,
      maxDuration: json['maxDuration'] as int?,
      shareWithAssistant: json['shareWithAssistant'] as bool? ?? false,
    );
  }
}
