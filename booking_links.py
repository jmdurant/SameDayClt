"""
Booking Link Generators

Generate booking URLs for flights and car rentals.
"""

from urllib.parse import urlencode
from datetime import datetime


def generate_google_flights_url(origin, destination, departure_date, return_date=None):
    """
    Generate a Google Flights URL for searching flights.

    Args:
        origin: Origin airport code (e.g., 'CLT')
        destination: Destination airport code (e.g., 'ATL')
        departure_date: Departure date in YYYY-MM-DD format
        return_date: Return date in YYYY-MM-DD format (optional, for round-trip)

    Returns:
        Google Flights URL string
    """
    if return_date:
        # Round trip
        flight_string = f"{origin}.{destination}.{departure_date}*{destination}.{origin}.{return_date}"
    else:
        # One way
        flight_string = f"{origin}.{destination}.{departure_date}"

    # Google Flights URL format
    url = f"https://www.google.com/flights?hl=en#flt={flight_string};c:USD;e:1;sd:1;t:f"
    return url


def generate_kayak_url(origin, destination, departure_date, return_date=None):
    """
    Generate a Kayak URL for searching flights.
    """
    if return_date:
        # Round trip
        url = f"https://www.kayak.com/flights/{origin}-{destination}/{departure_date}/{return_date}?sort=bestflight_a"
    else:
        # One way
        url = f"https://www.kayak.com/flights/{origin}-{destination}/{departure_date}?sort=bestflight_a"

    return url


def generate_airline_url(carrier_code, origin, destination, departure_date, return_date=None):
    """
    Generate airline-specific booking URL.

    Args:
        carrier_code: IATA airline code (e.g., 'AA', 'DL', 'UA')
        origin, destination: Airport codes
        departure_date, return_date: Dates in YYYY-MM-DD format

    Returns:
        Airline booking URL or generic search URL
    """
    # Map of airline codes to booking URL templates
    airline_urls = {
        'AA': 'https://www.aa.com/booking/search',  # American
        'DL': 'https://www.delta.com/flight-search/book-a-flight',  # Delta
        'UA': 'https://www.united.com/en/us/fsr/choose-flights',  # United
        'WN': 'https://www.southwest.com/air/booking/select.html',  # Southwest
        'B6': 'https://www.jetblue.com/booking/flights',  # JetBlue
        'AS': 'https://www.alaskaair.com/shopping/flights/search',  # Alaska
        'NK': 'https://www.spirit.com/book/flights',  # Spirit
        'F9': 'https://www.flyfrontier.com/travel/flight-search/',  # Frontier
    }

    base_url = airline_urls.get(carrier_code)

    if not base_url:
        # Fallback to Google Flights if airline not recognized
        return generate_google_flights_url(origin, destination, departure_date, return_date)

    # Most airlines use similar query parameters, but they vary
    # For simplicity, return the base search page
    # Users will need to enter dates manually (better than nothing)

    return base_url


def generate_turo_search_url(city, pickup_date, return_date, pickup_time="10:00", return_time="18:00"):
    """
    Generate Turo search URL for a city and date range.

    Args:
        city: City name (e.g., 'Atlanta')
        pickup_date: Date in YYYY-MM-DD format
        return_date: Date in YYYY-MM-DD format
        pickup_time: Time in HH:MM format (default: 10:00)
        return_time: Time in HH:MM format (default: 18:00)

    Returns:
        Turo search URL
    """
    # Format: https://turo.com/search?location=Atlanta&startDate=2025-10-30&startTime=10:00&endDate=2025-10-30&endTime=18:00

    params = {
        'location': city,
        'startDate': pickup_date,
        'startTime': pickup_time,
        'endDate': return_date,
        'endTime': return_time,
    }

    query_string = urlencode(params)
    url = f"https://turo.com/search?{query_string}"

    return url


def add_booking_links_to_trip(trip_dict):
    """
    Add booking link fields to a trip dictionary.

    Args:
        trip_dict: Dictionary with trip data

    Returns:
        Updated dictionary with booking link fields
    """
    origin = trip_dict.get('Origin', '')
    destination = trip_dict.get('Destination', '')
    date = trip_dict.get('Date', '')
    city = trip_dict.get('City', '')

    # Flight booking links
    trip_dict['Google Flights URL'] = generate_google_flights_url(
        origin, destination, date, date  # Same day return
    )

    trip_dict['Kayak URL'] = generate_kayak_url(
        origin, destination, date, date
    )

    # Extract carrier code from outbound flight
    outbound_flight = trip_dict.get('Outbound Flight', '')
    if outbound_flight:
        # Format is usually "AA1234, DL5678" - take first one
        carrier_code = outbound_flight.split(',')[0].strip()[:2]
        trip_dict['Airline URL'] = generate_airline_url(
            carrier_code, origin, destination, date, date
        )

    # Turo link (if not already provided by API)
    if not trip_dict.get('Turo URL'):
        arrive_dest = trip_dict.get('Arrive Destination', '10:00')
        depart_dest = trip_dict.get('Depart Destination', '18:00')

        trip_dict['Turo Search URL'] = generate_turo_search_url(
            city, date, date, arrive_dest, depart_dest
        )

    return trip_dict


# Example usage
if __name__ == '__main__':
    # Test the functions

    print("Google Flights URL:")
    print(generate_google_flights_url('CLT', 'ATL', '2025-10-30', '2025-10-30'))
    print()

    print("Kayak URL:")
    print(generate_kayak_url('CLT', 'ATL', '2025-10-30', '2025-10-30'))
    print()

    print("American Airlines URL:")
    print(generate_airline_url('AA', 'CLT', 'ATL', '2025-10-30', '2025-10-30'))
    print()

    print("Turo Search URL:")
    print(generate_turo_search_url('Atlanta', '2025-10-30', '2025-10-30', '10:00', '18:00'))
    print()

    # Test with a sample trip
    sample_trip = {
        'Origin': 'CLT',
        'Destination': 'ATL',
        'City': 'Atlanta',
        'Date': '2025-10-30',
        'Outbound Flight': 'AA1234, DL5678',
        'Arrive Destination': '10:00',
        'Depart Destination': '18:00',
    }

    updated_trip = add_booking_links_to_trip(sample_trip)

    print("Updated trip with booking links:")
    for key in ['Google Flights URL', 'Kayak URL', 'Airline URL', 'Turo Search URL']:
        if key in updated_trip:
            print(f"  {key}: {updated_trip[key]}")
