"""
Dynamic Same-Day Trip Finder

Finds all viable same-day round trips from any origin airport for any given date by:
1. Searching for all early morning departures (before 9 AM)
2. Searching for all evening returns (arriving 3-7 PM)
3. Matching valid pairings and calculating ground time
4. Outputting results with real-time pricing

Usage:
    # Basic - from Charlotte with defaults (depart by 9am, return 3pm-7pm)
    python find_same_day_trips.py --date 2025-11-15

    # From a different city
    python find_same_day_trips.py --origin LAX --date 2025-11-15

    # Custom time windows - leave earlier, return later
    python find_same_day_trips.py --date 2025-11-15 --depart-by 7 --return-after 17 --return-by 22

    # Ultra-early morning trips (red-eye style)
    python find_same_day_trips.py --date 2025-11-15 --depart-by 6 --return-by 20

    # More ground time - leave early, return late
    python find_same_day_trips.py --date 2025-11-15 --depart-by 8 --return-after 18 --min-ground-time 6

    # With destination filters
    python find_same_day_trips.py --date 2025-11-15 --destinations ATL MIA BOS
    python find_same_day_trips.py --date 2025-11-15 --limit 5
"""

import argparse
import pandas as pd
import requests
import time
from datetime import datetime, timedelta


# Amadeus API Configuration
AMADEUS_API_KEY = "zDYWXqUHNcmVPjvHVxBeTLK8pZGZ8KbI"
AMADEUS_API_SECRET = "QcuIX7JOc4G0AOdc"
AMADEUS_BASE_URL = "https://test.api.amadeus.com"

# Search criteria (overridden by command-line args)
# These are set dynamically in the function based on user input


def get_amadeus_token():
    """Authenticate with Amadeus API and get access token."""
    auth_url = f"{AMADEUS_BASE_URL}/v1/security/oauth2/token"
    auth_data = {
        "grant_type": "client_credentials",
        "client_id": AMADEUS_API_KEY,
        "client_secret": AMADEUS_API_SECRET
    }

    try:
        response = requests.post(auth_url, data=auth_data, timeout=30)
        response.raise_for_status()
        token_data = response.json()
        print("[SUCCESS] Amadeus API authenticated")
        return token_data['access_token']
    except Exception as e:
        print(f"[ERROR] Authentication failed: {e}")
        return None


def search_flights(token, origin, destination, date, max_results=50):
    """
    Search for flights between two airports on a specific date.
    Returns list of flight offers with schedule and price data.
    """
    url = f"{AMADEUS_BASE_URL}/v2/shopping/flight-offers"
    headers = {"Authorization": f"Bearer {token}"}
    params = {
        "originLocationCode": origin,
        "destinationLocationCode": destination,
        "departureDate": date,
        "adults": 1,
        "max": max_results,
        "currencyCode": "USD"
    }

    try:
        response = requests.get(url, headers=headers, params=params, timeout=30)
        response.raise_for_status()
        data = response.json()
        return data.get('data', [])
    except Exception as e:
        print(f"    [WARNING] Search failed: {e}")
        return []


def parse_flight_offer(offer):
    """
    Parse Amadeus flight offer to extract key details.

    Returns dict with:
        - depart_time: datetime object
        - arrive_time: datetime object
        - duration_minutes: int
        - price: float
        - flight_numbers: str (e.g., "AA1234, DL5678")
        - num_stops: int
    """
    itinerary = offer['itineraries'][0]
    segments = itinerary['segments']

    # Get first segment departure and last segment arrival
    first_segment = segments[0]
    last_segment = segments[-1]

    depart_time = datetime.fromisoformat(first_segment['departure']['at'].replace('Z', '+00:00'))
    arrive_time = datetime.fromisoformat(last_segment['arrival']['at'].replace('Z', '+00:00'))

    # Calculate duration in minutes
    duration_str = itinerary['duration']  # Format: "PT2H15M"
    duration_minutes = parse_duration(duration_str)

    # Get flight numbers
    flight_numbers = ', '.join([seg['carrierCode'] + seg['number'] for seg in segments])

    # Number of stops
    num_stops = len(segments) - 1

    # Price
    price = float(offer['price']['total'])

    return {
        'depart_time': depart_time,
        'arrive_time': arrive_time,
        'duration_minutes': duration_minutes,
        'flight_numbers': flight_numbers,
        'num_stops': num_stops,
        'price': price
    }


def parse_duration(duration_str):
    """
    Parse ISO 8601 duration format to minutes.
    Example: "PT2H15M" -> 135 minutes
    """
    import re
    hours = 0
    minutes = 0

    hour_match = re.search(r'(\d+)H', duration_str)
    min_match = re.search(r'(\d+)M', duration_str)

    if hour_match:
        hours = int(hour_match.group(1))
    if min_match:
        minutes = int(min_match.group(1))

    return hours * 60 + minutes


def filter_outbound_flights(flights, max_depart_hour, max_duration, debug=False):
    """
    Filter flights to only early departures.
    Criteria: Depart before max_depart_hour (local time), duration < max_duration
    """
    filtered = []
    for flight in flights:
        parsed = parse_flight_offer(flight)

        # Convert to local time (remove timezone for hour comparison)
        local_depart_hour = parsed['depart_time'].hour

        if debug:  # Show all for debugging
            print(f"      Flight @ {format_time(parsed['depart_time'])}, duration {parsed['duration_minutes']}min, stops: {parsed['num_stops']} - "
                  f"{'PASS' if local_depart_hour < max_depart_hour and parsed['duration_minutes'] <= max_duration else 'FAIL'}")

        if (local_depart_hour < max_depart_hour and
            parsed['duration_minutes'] <= max_duration):
            filtered.append(parsed)

    return filtered


def filter_return_flights(flights, min_arrive_hour, max_arrive_hour, max_duration):
    """
    Filter flights to arrivals within time window.
    Criteria: Arrive between min_arrive_hour and max_arrive_hour (local time), duration < max_duration
    """
    filtered = []
    for flight in flights:
        parsed = parse_flight_offer(flight)

        # Convert to local time (remove timezone for hour comparison)
        local_arrive_hour = parsed['arrive_time'].hour

        if (min_arrive_hour <= local_arrive_hour < max_arrive_hour and
            parsed['duration_minutes'] <= max_duration):
            filtered.append(parsed)

    return filtered


def calculate_ground_time(outbound_arrival, return_departure):
    """
    Calculate ground time between landing and takeoff.
    Returns hours as a float.
    """
    ground_time_delta = return_departure - outbound_arrival
    return ground_time_delta.total_seconds() / 3600


def format_time(dt):
    """Format datetime as HH:MM string."""
    return dt.strftime('%H:%M')


def format_duration(minutes):
    """Format minutes as 'Xh YYm' string."""
    hours = minutes // 60
    mins = minutes % 60
    return f"{hours}h {mins:02d}m"


def find_same_day_trips_for_destination(token, origin, destination, city_name, date,
                                        min_ground_time, max_duration,
                                        max_depart_hour, min_return_hour, max_return_hour):
    """
    Find all viable same-day trip pairings for a single destination.

    Returns list of dicts with trip details.
    """
    print(f"\n[Searching] {destination} - {city_name}")

    trips = []

    # Search outbound flights (origin -> destination)
    print(f"  Outbound: {origin} -> {destination}")
    outbound_offers = search_flights(token, origin, destination, date)
    print(f"    API returned {len(outbound_offers)} total outbound flights")
    outbound_flights = filter_outbound_flights(outbound_offers, max_depart_hour, max_duration, debug=False)
    print(f"    Found {len(outbound_flights)} early flights (depart < {max_depart_hour}:00)")

    if not outbound_flights:
        return trips

    time.sleep(0.5)  # Be nice to the API

    # Search return flights (destination -> origin)
    print(f"  Return: {destination} -> {origin}")
    return_offers = search_flights(token, destination, origin, date)
    return_flights = filter_return_flights(return_offers, min_return_hour, max_return_hour, max_duration)
    print(f"    Found {len(return_flights)} return flights (arrive {min_return_hour}:00-{max_return_hour}:00)")

    if not return_flights:
        return trips

    # Match all valid pairings
    print(f"  Matching pairings...")
    for outbound in outbound_flights:
        for return_flight in return_flights:
            # Calculate ground time
            ground_time_hours = calculate_ground_time(
                outbound['arrive_time'],
                return_flight['depart_time']
            )

            # Check if ground time meets minimum threshold
            if ground_time_hours >= min_ground_time:
                trips.append({
                    'Origin': origin,
                    'Destination': destination,
                    'City': city_name,
                    'Date': date,

                    # Outbound
                    'Outbound Flight': outbound['flight_numbers'],
                    'Outbound Stops': outbound['num_stops'],
                    f'Depart {origin}': format_time(outbound['depart_time']),
                    'Arrive Destination': format_time(outbound['arrive_time']),
                    'Outbound Duration': format_duration(outbound['duration_minutes']),
                    'Outbound Price': outbound['price'],

                    # Return
                    'Return Flight': return_flight['flight_numbers'],
                    'Return Stops': return_flight['num_stops'],
                    'Depart Destination': format_time(return_flight['depart_time']),
                    f'Arrive {origin}': format_time(return_flight['arrive_time']),
                    'Return Duration': format_duration(return_flight['duration_minutes']),
                    'Return Price': return_flight['price'],

                    # Totals
                    'Ground Time (hours)': round(ground_time_hours, 2),
                    'Ground Time': format_duration(int(ground_time_hours * 60)),
                    'Total Flight Cost': outbound['price'] + return_flight['price'],
                    'Total Trip Time': format_duration(
                        outbound['duration_minutes'] +
                        int(ground_time_hours * 60) +
                        return_flight['duration_minutes']
                    )
                })

    print(f"  Found {len(trips)} viable same-day trip combinations")

    return trips


def load_destinations(input_file):
    """Load destination list from existing spreadsheet."""
    try:
        df = pd.read_excel(input_file, sheet_name='Best Same-Day Trips')
        destinations = []
        for _, row in df.iterrows():
            destinations.append({
                'code': row['Destination'],
                'city': row['City']
            })
        return destinations
    except Exception as e:
        print(f"[WARNING] Could not load destinations from {input_file}: {e}")
        return None


def main():
    parser = argparse.ArgumentParser(description='Find all same-day trips from CLT for any date')
    parser.add_argument('--date', required=True, help='Travel date (YYYY-MM-DD)')
    parser.add_argument('--origin', default='CLT', help='Origin airport code (default: CLT)')

    # Time window parameters
    parser.add_argument('--depart-by', type=int, default=9,
                       help='Latest departure hour in 24hr format (default: 9 = 9:00 AM)')
    parser.add_argument('--return-after', type=int, default=15,
                       help='Earliest return arrival hour in 24hr format (default: 15 = 3:00 PM)')
    parser.add_argument('--return-by', type=int, default=19,
                       help='Latest return arrival hour in 24hr format (default: 19 = 7:00 PM)')

    # Ground time and duration parameters
    parser.add_argument('--min-ground-time', type=float, default=3.0,
                       help='Minimum ground time in hours (default: 3.0)')
    parser.add_argument('--max-duration', type=int, default=204,
                       help='Maximum flight duration in minutes (default: 204 = 3h 24m)')

    parser.add_argument('--destinations', nargs='+',
                       help='Specific destinations to search (e.g., ATL MIA BOS)')
    parser.add_argument('--limit', type=int,
                       help='Limit to first N destinations (for testing)')
    parser.add_argument('--input', default='CLT_Same_Day_Trips_UPDATED.xlsx',
                       help='Input file with destination list')
    parser.add_argument('--output',
                       help='Output file (default: CLT_Same_Day_Trips_YYYY-MM-DD.xlsx)')
    args = parser.parse_args()

    # Set output filename
    if not args.output:
        args.output = f"{args.origin}_Same_Day_Trips_{args.date}.xlsx"

    print("=" * 70)
    print("DYNAMIC SAME-DAY TRIP FINDER")
    print("=" * 70)
    print(f"Origin: {args.origin}")
    print(f"Date: {args.date}")
    print(f"Depart by: {args.depart_by}:00 (before {args.depart_by}:00)")
    print(f"Return window: {args.return_after}:00 - {args.return_by}:00")
    print(f"Minimum ground time: {args.min_ground_time} hours")
    print(f"Max flight duration: {args.max_duration} minutes")
    print(f"Output: {args.output}")
    print("=" * 70)

    # Authenticate
    token = get_amadeus_token()
    if not token:
        print("[ERROR] Cannot proceed without authentication")
        return

    print()

    # Load destinations
    destinations = load_destinations(args.input)
    if not destinations:
        print("[ERROR] No destinations loaded. Using fallback list.")
        # Fallback to some common destinations
        destinations = [
            {'code': 'ATL', 'city': 'Atlanta'},
            {'code': 'MIA', 'city': 'Miami'},
            {'code': 'BOS', 'city': 'Boston'}
        ]

    print(f"Loaded {len(destinations)} destinations")

    # Filter by specific destinations if requested
    if args.destinations:
        dest_codes = [d.upper() for d in args.destinations]
        destinations = [d for d in destinations if d['code'] in dest_codes]
        print(f"Filtered to {len(destinations)} destinations: {', '.join(dest_codes)}")

    # Limit if requested
    if args.limit:
        destinations = destinations[:args.limit]
        print(f"Limited to first {args.limit} destinations")

    print()
    print("=" * 70)
    print("SEARCHING FOR TRIPS")
    print("=" * 70)

    # Process each destination
    all_trips = []
    for i, dest in enumerate(destinations, 1):
        print(f"\n[{i}/{len(destinations)}] Processing {dest['code']} - {dest['city']}")

        trips = find_same_day_trips_for_destination(
            token,
            args.origin.upper(),
            dest['code'],
            dest['city'],
            args.date,
            args.min_ground_time,
            args.max_duration,
            args.depart_by,
            args.return_after,
            args.return_by
        )

        all_trips.extend(trips)

        # Delay between destinations
        time.sleep(1)

    # Save results
    print()
    print("=" * 70)
    print("RESULTS")
    print("=" * 70)
    print(f"Total viable trip combinations found: {len(all_trips)}")

    if len(all_trips) > 0:
        df = pd.DataFrame(all_trips)

        # Sort by destination, then by total cost
        df = df.sort_values(['Destination', 'Total Flight Cost'])

        # Add rank within each destination (1 = cheapest)
        df['Rank for Destination'] = df.groupby('Destination')['Total Flight Cost'].rank(method='first')

        # Mark best option for each destination
        df['Best Option'] = df['Rank for Destination'] == 1

        # Save to Excel
        df.to_excel(args.output, index=False, sheet_name='All Same-Day Trips')

        print(f"Saved to: {args.output}")

        # Print summary by destination
        print()
        print("Summary by destination:")
        summary = df.groupby('Destination').agg({
            'City': 'first',
            'Destination': 'count',
            'Ground Time (hours)': 'max',
            'Total Flight Cost': 'min'
        }).rename(columns={'Destination': 'Num Options'})
        print(summary.to_string())

    else:
        print("No viable trips found for the selected criteria.")

    print()
    print("=" * 70)
    print("COMPLETE!")
    print("=" * 70)


if __name__ == "__main__":
    main()
