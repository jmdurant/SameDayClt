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
  ///
  /// Note: Some offsets overlap during DST transitions (e.g., -05:00 could be EST or CDT).
  /// We map to the most common/populous timezone for each offset.
  static String _offsetToAbbreviation(String offset) {
    // Map timezone offsets to abbreviations (one mapping per offset)
    // Prioritizes standard time zones (larger populations)
    switch (offset) {
      case '-04:00':
        return 'ET';  // EDT (Eastern Daylight) - only ET uses -04:00
      case '-05:00':
        return 'ET';  // EST (Eastern Standard) - prefer EST over CDT (more populous)
      case '-06:00':
        return 'CT';  // CST (Central Standard) - prefer CST over MDT
      case '-07:00':
        return 'MT';  // MST (Mountain Standard) - prefer MST over PDT
      case '-08:00':
        return 'PT';  // PST (Pacific Standard) - prefer PST over AKDT (more populous)
      case '-09:00':
        return 'AKT'; // AKST (Alaska Standard)
      case '-10:00':
        return 'HT';  // HST (Hawaii Standard, no DST)
      case '+00:00':
        return 'GMT'; // Greenwich Mean Time
      case '+01:00':
        return 'CET'; // Central European Time
      default:
        // Format unknown offsets as "UTC±H"
        final sign = offset.startsWith('-') ? '-' : '+';
        final hours = int.tryParse(offset.substring(1, 3)) ?? 0;
        return 'UTC$sign$hours';
    }
  }
}
