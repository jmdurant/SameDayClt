class Trip {
  final String origin;
  final String destination;
  final String city;
  final String date;

  final String outboundFlight;
  final int outboundStops;
  final String departOrigin;
  final String arriveDestination;
  final String outboundDuration;
  final double outboundPrice;

  final String returnFlight;
  final int returnStops;
  final String departDestination;
  final String arriveOrigin;
  final String returnDuration;
  final double returnPrice;

  // Raw ISO timestamps for agenda generation
  final String? departOriginIso;
  final String? arriveDestinationIso;
  final String? departDestinationIso;
  final String? arriveOriginIso;

  // Timezone offsets (e.g., "-05:00", "+01:00")
  final String? departOriginTz;
  final String? arriveDestinationTz;
  final String? departDestinationTz;
  final String? arriveOriginTz;

  final double groundTimeHours;
  final String groundTime;
  final double totalFlightCost;
  final String totalTripTime;

  // Optional fields (loaded on demand)
  double? turoPrice;
  String? awardMilesOutboundMain;
  String? awardMilesOutboundFirst;
  String? awardMilesReturnMain;
  String? awardMilesReturnFirst;

  // Loading states
  bool isLoadingTuro = false;
  bool isLoadingRewards = false;

  // Coordinates for map
  final double? destLat;
  final double? destLng;

  // Booking URLs
  final String? googleFlightsUrl;
  final String? kayakUrl;
  final String? airlineUrl;
  final String? turoUrl;
  final String? turoSearchUrl;
  final String? turoVehicle;
  final String? offerId; // Duffel offer id for checkout links

  Trip({
    required this.origin,
    required this.destination,
    required this.city,
    required this.date,
    required this.outboundFlight,
    required this.outboundStops,
    required this.departOrigin,
    required this.arriveDestination,
    required this.outboundDuration,
    required this.outboundPrice,
    required this.returnFlight,
    required this.returnStops,
    required this.departDestination,
    required this.arriveOrigin,
    required this.returnDuration,
    required this.returnPrice,
    this.departOriginIso,
    this.arriveDestinationIso,
    this.departDestinationIso,
    this.arriveOriginIso,
    this.departOriginTz,
    this.arriveDestinationTz,
    this.departDestinationTz,
    this.arriveOriginTz,
    required this.groundTimeHours,
    required this.groundTime,
    required this.totalFlightCost,
    required this.totalTripTime,
    this.turoPrice,
    this.awardMilesOutboundMain,
    this.awardMilesOutboundFirst,
    this.awardMilesReturnMain,
    this.awardMilesReturnFirst,
    this.destLat,
    this.destLng,
    this.googleFlightsUrl,
    this.kayakUrl,
    this.airlineUrl,
    this.turoUrl,
    this.turoSearchUrl,
    this.turoVehicle,
    this.offerId,
  });

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      origin: json['Origin'] ?? '',
      destination: json['Destination'] ?? '',
      city: json['City'] ?? '',
      date: json['Date'] ?? '',
      outboundFlight: json['Outbound Flight'] ?? '',
      outboundStops: json['Outbound Stops'] ?? 0,
      departOrigin: json['Depart ${json['Origin']}'] ?? json['Depart CLT'] ?? '',
      arriveDestination: json['Arrive Destination'] ?? '',
      outboundDuration: json['Outbound Duration'] ?? '',
      outboundPrice: (json['Outbound Price'] ?? 0.0).toDouble(),
      returnFlight: json['Return Flight'] ?? '',
      returnStops: json['Return Stops'] ?? 0,
      departDestination: json['Depart Destination'] ?? '',
      arriveOrigin: json['Arrive ${json['Origin']}'] ?? json['Arrive CLT'] ?? '',
      returnDuration: json['Return Duration'] ?? '',
      returnPrice: (json['Return Price'] ?? 0.0).toDouble(),
      departOriginIso: json['Depart Origin ISO'],
      arriveDestinationIso: json['Arrive Destination ISO'],
      departDestinationIso: json['Depart Destination ISO'],
      arriveOriginIso: json['Arrive Origin ISO'],
      departOriginTz: json['Depart Origin TZ'],
      arriveDestinationTz: json['Arrive Destination TZ'],
      departDestinationTz: json['Depart Destination TZ'],
      arriveOriginTz: json['Arrive Origin TZ'],
      groundTimeHours: (json['Ground Time (hours)'] ?? 0.0).toDouble(),
      groundTime: json['Ground Time'] ?? '',
      totalFlightCost: (json['Total Flight Cost'] ?? 0.0).toDouble(),
      totalTripTime: json['Total Trip Time'] ?? '',
      destLat: json['lat']?.toDouble(),
      destLng: json['lng']?.toDouble(),
      googleFlightsUrl: json['Google Flights URL'],
      kayakUrl: json['Kayak URL'],
      airlineUrl: json['Airline URL'],
      turoUrl: json['Turo URL'],
      turoSearchUrl: json['Turo Search URL'],
      turoVehicle: json['Turo Vehicle'],
      offerId: json['OfferId'] ?? json['offerId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'Origin': origin,
      'Destination': destination,
      'City': city,
      'Date': date,
      'Outbound Flight': outboundFlight,
      'Outbound Stops': outboundStops,
      'Depart $origin': departOrigin,
      'Arrive Destination': arriveDestination,
      'Outbound Duration': outboundDuration,
      'Outbound Price': outboundPrice,
      'Return Flight': returnFlight,
      'Return Stops': returnStops,
      'Depart Destination': departDestination,
      'Arrive $origin': arriveOrigin,
      'Return Duration': returnDuration,
      'Return Price': returnPrice,
      'Depart Origin ISO': departOriginIso,
      'Arrive Destination ISO': arriveDestinationIso,
      'Depart Destination ISO': departDestinationIso,
      'Arrive Origin ISO': arriveOriginIso,
      'Depart Origin TZ': departOriginTz,
      'Arrive Destination TZ': arriveDestinationTz,
      'Depart Destination TZ': departDestinationTz,
      'Arrive Origin TZ': arriveOriginTz,
      'Ground Time (hours)': groundTimeHours,
      'Ground Time': groundTime,
      'Total Flight Cost': totalFlightCost,
      'Total Trip Time': totalTripTime,
      'lat': destLat,
      'lng': destLng,
      'Google Flights URL': googleFlightsUrl,
      'Kayak URL': kayakUrl,
      'Airline URL': airlineUrl,
      'Turo URL': turoUrl,
      'Turo Search URL': turoSearchUrl,
      'Turo Vehicle': turoVehicle,
      'OfferId': offerId,
    };
  }

  Trip copyWith({
    double? turoPrice,
    String? awardMilesOutboundMain,
    String? awardMilesOutboundFirst,
    String? awardMilesReturnMain,
    String? awardMilesReturnFirst,
    bool? isLoadingTuro,
    bool? isLoadingRewards,
    String? offerId,
  }) {
    return Trip(
      origin: origin,
      destination: destination,
      city: city,
      date: date,
      outboundFlight: outboundFlight,
      outboundStops: outboundStops,
      departOrigin: departOrigin,
      arriveDestination: arriveDestination,
      outboundDuration: outboundDuration,
      outboundPrice: outboundPrice,
      returnFlight: returnFlight,
      returnStops: returnStops,
      departDestination: departDestination,
      arriveOrigin: arriveOrigin,
      returnDuration: returnDuration,
      returnPrice: returnPrice,
      departOriginIso: departOriginIso,
      arriveDestinationIso: arriveDestinationIso,
      departDestinationIso: departDestinationIso,
      arriveOriginIso: arriveOriginIso,
      departOriginTz: departOriginTz,
      arriveDestinationTz: arriveDestinationTz,
      departDestinationTz: departDestinationTz,
      arriveOriginTz: arriveOriginTz,
      groundTimeHours: groundTimeHours,
      groundTime: groundTime,
      totalFlightCost: totalFlightCost,
      totalTripTime: totalTripTime,
      turoPrice: turoPrice ?? this.turoPrice,
      awardMilesOutboundMain: awardMilesOutboundMain ?? this.awardMilesOutboundMain,
      awardMilesOutboundFirst: awardMilesOutboundFirst ?? this.awardMilesOutboundFirst,
      awardMilesReturnMain: awardMilesReturnMain ?? this.awardMilesReturnMain,
      awardMilesReturnFirst: awardMilesReturnFirst ?? this.awardMilesReturnFirst,
      destLat: destLat,
      destLng: destLng,
      googleFlightsUrl: googleFlightsUrl,
      kayakUrl: kayakUrl,
      airlineUrl: airlineUrl,
      turoUrl: turoUrl ?? this.turoUrl,
      turoSearchUrl: turoSearchUrl,
      turoVehicle: turoVehicle ?? this.turoVehicle,
      offerId: offerId ?? this.offerId,
    )..isLoadingTuro = isLoadingTuro ?? this.isLoadingTuro
     ..isLoadingRewards = isLoadingRewards ?? this.isLoadingRewards;
  }
}
