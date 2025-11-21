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
      'CLE': 'ET', 'BNA': 'ET', 'MEM': 'ET', 'JAX': 'ET', 'RSW': 'ET',
      'PBI': 'ET', 'SDF': 'ET', 'BUF': 'ET', 'ROC': 'ET', 'SYR': 'ET',

      // Central Time
      'ORD': 'CT', 'DFW': 'CT', 'IAH': 'CT', 'MSP': 'CT', 'DAL': 'CT',
      'STL': 'CT', 'MDW': 'CT', 'HOU': 'CT', 'AUS': 'CT', 'SAT': 'CT',
      'MSY': 'CT', 'MKE': 'CT', 'MCI': 'CT', 'OMA': 'CT', 'DSM': 'CT',
      'OKC': 'CT', 'TUL': 'CT', 'LIT': 'CT', 'XNA': 'CT', 'HSV': 'CT',
      'MOB': 'CT', 'GPT': 'CT', 'BTR': 'CT', 'SHV': 'CT', 'GRR': 'CT',

      // Mountain Time
      'DEN': 'MT', 'PHX': 'MT', 'SLC': 'MT', 'ABQ': 'MT', 'ELP': 'MT',
      'TUS': 'MT', 'BOI': 'MT', 'BIL': 'MT', 'MSO': 'MT', 'GEG': 'PT',
      'COS': 'MT', 'BZN': 'MT', 'JAC': 'MT', 'FCA': 'MT',

      // Pacific Time (note: LAS/Phoenix don't observe DST, but we use PT/MT for simplicity)
      'LAX': 'PT', 'SFO': 'PT', 'SEA': 'PT', 'SAN': 'PT', 'PDX': 'PT',
      'SJC': 'PT', 'OAK': 'PT', 'SMF': 'PT', 'BUR': 'PT', 'ONT': 'PT',
      'LAS': 'PT', 'RNO': 'PT', 'SNA': 'PT', 'LGB': 'PT', 'PSP': 'PT',

      // Alaska Time
      'ANC': 'AKT', 'FAI': 'AKT', 'JNU': 'AKT',

      // Hawaii Time
      'HNL': 'HT', 'OGG': 'HT', 'KOA': 'HT', 'LIH': 'HT',
    };

    return timezones[airportCode.toUpperCase()] ?? '';
  }

  /// Format time with timezone using actual timezone offset from API
  /// Example: "14:30" with offset "-05:00" -> "2:30 PM ET"
  /// Falls back to airport code if offset not available: "2:30 PM JFK"
  static String formatWithTimezone(String time24, String airportCode, {String? tzOffset}) {
    final time12 = to12Hour(time24);

    // Prefer timezone offset from API if available
    if (tzOffset != null && tzOffset.isNotEmpty) {
      final tzAbbr = _offsetToAbbreviation(tzOffset);
      return '$time12 $tzAbbr';
    }

    // Fall back to airport code lookup
    final tz = getTimezone(airportCode);
    final tzDisplay = tz.isNotEmpty ? tz : airportCode.toUpperCase();
    return '$time12 $tzDisplay';
  }

  /// Convert timezone offset to abbreviation
  /// Example: "-05:00" -> "ET", "-08:00" -> "PT"
  static String _offsetToAbbreviation(String offset) {
    // Map common US timezone offsets to abbreviations
    // Note: This is simplified and doesn't account for DST changes
    final Map<String, String> offsetToTz = {
      '-05:00': 'ET',  // Eastern Time
      '-04:00': 'ET',  // Eastern Daylight Time
      '-06:00': 'CT',  // Central Time
      '-05:00': 'CT',  // Central Daylight Time (conflicts with ET, will use first match)
      '-07:00': 'MT',  // Mountain Time
      '-06:00': 'MT',  // Mountain Daylight Time (conflicts with CT)
      '-08:00': 'PT',  // Pacific Time
      '-07:00': 'PT',  // Pacific Daylight Time (conflicts with MT)
      '-09:00': 'AKT', // Alaska Time
      '-08:00': 'AKT', // Alaska Daylight Time (conflicts with PT)
      '-10:00': 'HT',  // Hawaii Time
      '+00:00': 'GMT', // Greenwich Mean Time
      '+01:00': 'CET', // Central European Time
    };

    // Try to find a match, otherwise return the offset itself (e.g., "UTC-5")
    if (offsetToTz.containsKey(offset)) {
      return offsetToTz[offset]!;
    }

    // Format offset as "UTC±H" for unknown timezones
    final sign = offset.startsWith('-') ? '-' : '+';
    final hours = int.tryParse(offset.substring(1, 3)) ?? 0;
    return 'UTC$sign$hours';
  }
}
