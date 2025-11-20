/// Utility functions for formatting times
class TimeFormatter {
  /// Convert 24-hour time string (e.g., "14:30") to 12-hour format with AM/PM
  /// Example: "14:30" -> "2:30 PM"
  static String to12Hour(String time24) {
    if (time24.isEmpty) return time24;

    try {
      // Handle times like "14:30" or "09:15"
      final parts = time24.split(':');
      if (parts.length < 2) return time24;

      int hour = int.parse(parts[0]);
      final minute = parts[1];

      final period = hour >= 12 ? 'PM' : 'AM';

      // Convert hour to 12-hour format
      if (hour == 0) {
        hour = 12; // Midnight
      } else if (hour > 12) {
        hour = hour - 12;
      }

      return '$hour:$minute $period';
    } catch (e) {
      // If parsing fails, return original
      return time24;
    }
  }

  /// Get timezone abbreviation for an airport code
  /// This is a simplified version - in production you'd use a proper timezone database
  static String getTimezone(String airportCode) {
    // Map of common US airport codes to timezone abbreviations
    final Map<String, String> timezones = {
      // Eastern Time
      'ATL': 'ET', 'CLT': 'ET', 'MIA': 'ET', 'JFK': 'ET', 'LGA': 'ET',
      'EWR': 'ET', 'BOS': 'ET', 'DCA': 'ET', 'IAD': 'ET', 'BWI': 'ET',
      'PHL': 'ET', 'DTW': 'ET', 'MCO': 'ET', 'FLL': 'ET', 'TPA': 'ET',
      'RDU': 'ET', 'PIT': 'ET', 'CVG': 'ET', 'CMH': 'ET', 'IND': 'ET',

      // Central Time
      'ORD': 'CT', 'DFW': 'CT', 'IAH': 'CT', 'DEN': 'MT', 'MSP': 'CT',
      'STL': 'CT', 'MDW': 'CT', 'HOU': 'CT', 'AUS': 'CT', 'SAT': 'CT',
      'MSY': 'CT', 'MKE': 'CT', 'MCI': 'CT', 'OMA': 'CT', 'DSM': 'CT',

      // Mountain Time
      'DEN': 'MT', 'PHX': 'MT', 'SLC': 'MT', 'LAS': 'PT', 'ABQ': 'MT',
      'TUS': 'MT', 'BOI': 'MT', 'BIL': 'MT', 'MSO': 'MT',

      // Pacific Time
      'LAX': 'PT', 'SFO': 'PT', 'SEA': 'PT', 'SAN': 'PT', 'PDX': 'PT',
      'SJC': 'PT', 'OAK': 'PT', 'SMF': 'PT', 'BUR': 'PT', 'ONT': 'PT',

      // Alaska Time
      'ANC': 'AKT', 'FAI': 'AKT', 'JNU': 'AKT',

      // Hawaii Time
      'HNL': 'HT', 'OGG': 'HT', 'KOA': 'HT', 'LIH': 'HT',
    };

    return timezones[airportCode.toUpperCase()] ?? '';
  }

  /// Format time with timezone
  /// Example: "14:30" for "LAX" -> "2:30 PM PT"
  static String formatWithTimezone(String time24, String airportCode) {
    final time12 = to12Hour(time24);
    final tz = getTimezone(airportCode);

    if (tz.isEmpty) {
      return time12;
    }

    return '$time12 $tz';
  }
}
