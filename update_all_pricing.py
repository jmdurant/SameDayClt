"""
Master pricing updater for CLT Same-Day Trips.

Single script that updates ALL pricing in the spreadsheet:
- Amadeus API: Real cash flight prices (outbound/return)
- AA Award Availability: Miles required (Main/First for outbound/return)
- Turo Car Rental: Real rental prices via Apify scraper

Usage:
    python update_all_pricing.py --date 2025-11-15
    python update_all_pricing.py --date 2025-11-15 --skip-cash  # Only update awards
    python update_all_pricing.py --date 2025-11-15 --skip-awards  # Only update cash
    python update_all_pricing.py --date 2025-11-15 --skip-turo  # Skip car rental pricing
    python update_all_pricing.py --date 2025-11-15 --apify-token YOUR_TOKEN  # Use your Apify API token
"""

import pandas as pd
import argparse
import time
import sys
import os
from datetime import datetime, timedelta
import requests

# Add the aa_flight_search_tool directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'aa_flight_search_tool'))

from search_aa_award_flights import scrape_flight_page, generate_url
import undetected_chromedriver as uc


# ============================================================================
# AMADEUS API - CASH PRICING
# ============================================================================

AMADEUS_API_KEY = "zDYWXqUHNcmVPjvHVxBeTLK8pZGZ8KbI"
AMADEUS_API_SECRET = "QcuIX7JOc4G0AOdc"
AMADEUS_BASE_URL = "https://test.api.amadeus.com"

# ============================================================================
# APIFY / TURO INTEGRATION
# ============================================================================

APIFY_TURO_ACTOR_ID = "MrlcWebEaPAMtKAas"
APIFY_API_BASE = "https://api.apify.com/v2"


def get_amadeus_token():
    """Get Amadeus API access token."""
    auth_url = f"{AMADEUS_BASE_URL}/v1/security/oauth2/token"
    auth_data = {
        "grant_type": "client_credentials",
        "client_id": AMADEUS_API_KEY,
        "client_secret": AMADEUS_API_SECRET
    }
    response = requests.post(auth_url, data=auth_data)
    response.raise_for_status()
    return response.json()['access_token']


def search_amadeus_flights(token, origin, destination, date, adults=1):
    """Search for flights using Amadeus API."""
    url = f"{AMADEUS_BASE_URL}/v2/shopping/flight-offers"
    headers = {"Authorization": f"Bearer {token}"}
    params = {
        "originLocationCode": origin,
        "destinationLocationCode": destination,
        "departureDate": date,
        "adults": adults,
        "max": 10,
        "currencyCode": "USD"
    }

    response = requests.get(url, headers=headers, params=params, timeout=30)
    response.raise_for_status()
    return response.json()


def find_flight_by_time(offers, target_time, max_time_diff_minutes=60):
    """
    Find flight matching target departure time.
    Prioritizes direct flights, returns price if found within time window.

    Args:
        offers: Amadeus API response with flight offers
        target_time: Target departure time as string "HH:MM"
        max_time_diff_minutes: Maximum difference in minutes to consider a match

    Returns:
        Price of matching flight or None
    """
    # Parse target time
    target_hour, target_min = map(int, target_time.split(':'))
    target_minutes = target_hour * 60 + target_min

    best_match_price = None
    best_match_diff = float('inf')
    best_is_direct = False

    for offer in offers.get('data', []):
        # Get departure time from first segment
        departure_time = offer['itineraries'][0]['segments'][0]['departure']['at']
        # Parse: "2025-11-17T05:30:00"
        dep_time_str = departure_time.split('T')[1][:5]  # Get "05:30"
        dep_hour, dep_min = map(int, dep_time_str.split(':'))
        dep_minutes = dep_hour * 60 + dep_min

        # Calculate time difference
        diff = abs(dep_minutes - target_minutes)

        # Check if it's direct
        is_direct = len(offer['itineraries'][0]['segments']) == 1
        price = float(offer['price']['total'])

        # Update best match if:
        # 1. Within time window AND
        # 2. (Closer time match OR same time but direct flight OR same time/directness but cheaper)
        if diff <= max_time_diff_minutes:
            if (diff < best_match_diff or
                (diff == best_match_diff and is_direct and not best_is_direct) or
                (diff == best_match_diff and is_direct == best_is_direct and price < best_match_price)):
                best_match_price = price
                best_match_diff = diff
                best_is_direct = is_direct

    return best_match_price


def fetch_cash_pricing(token, origin, destination, date, target_time):
    """
    Fetch cash pricing for a specific flight matching target departure time.

    Args:
        token: Amadeus API token
        origin: Origin airport code
        destination: Destination airport code
        date: Travel date YYYY-MM-DD
        target_time: Target departure time HH:MM
    """
    try:
        offers = search_amadeus_flights(token, origin, destination, date)
        price = find_flight_by_time(offers, target_time)
        return price
    except Exception as e:
        print(f"    Error fetching cash price: {e}")
        return None


# ============================================================================
# AA AWARD PRICING
# ============================================================================

def find_matching_flight(flights, depart_time_target, max_time_diff_minutes=30):
    """Find flight closest to target departure time."""
    if not flights:
        return None

    target_hour, target_min = map(int, depart_time_target.split(':'))
    target_minutes = target_hour * 60 + target_min

    print(f"    [DEBUG] Target time: {depart_time_target}, Found {len(flights)} flights")
    print(f"    [DEBUG] Flight times available:", [f"{f['depart_time'].hour:02d}:{f['depart_time'].minute:02d}" for f in flights[:5]], "...")

    best_match = None
    best_diff = float('inf')

    for flight in flights:
        flight_time = flight['depart_time']
        flight_minutes = flight_time.hour * 60 + flight_time.minute
        diff = abs(flight_minutes - target_minutes)

        if diff < best_diff and diff <= max_time_diff_minutes:
            best_diff = diff
            best_match = flight

    if best_match:
        print(f"    [DEBUG] Best match: {best_match['depart_time'].hour:02d}:{best_match['depart_time'].minute:02d} (diff: {best_diff} min)")
    else:
        print(f"    [DEBUG] No match within {max_time_diff_minutes} minutes")

    return best_match


def fetch_award_pricing(driver, origin, destination, date, target_depart_time, sleep_sec=3):
    """Fetch award pricing for a specific route."""
    url = generate_url(
        depart_date=date,
        origin=origin,
        destination=destination,
        n_adults=1,
        n_children=0
    )

    try:
        flights = scrape_flight_page(url, driver, sleep_sec=sleep_sec)
        if not flights:
            return None

        matching_flight = find_matching_flight(flights, target_depart_time)
        if not matching_flight:
            return None

        return {
            'main': matching_flight.get('num_miles_main'),
            'first': matching_flight.get('num_miles_first')
        }
    except Exception as e:
        print(f"    Error fetching award: {e}")
        return None


# ============================================================================
# TURO CAR RENTAL PRICING (via Apify)
# ============================================================================

def fetch_turo_pricing(apify_token, city_name, pickup_datetime, return_datetime, age=25):
    """
    Fetch Turo car rental pricing for a specific city and date range.

    Args:
        apify_token: Apify API token
        city_name: City name (e.g., "atlanta", "miami")
        pickup_datetime: Pickup datetime string (e.g., "2025-11-15T08:00")
        return_datetime: Return datetime string (e.g., "2025-11-15T18:00")
        age: Driver age

    Returns:
        Lowest avgDailyPrice or None if failed
    """
    if not apify_token:
        return None

    try:
        # Start the Apify actor run
        run_url = f"{APIFY_API_BASE}/acts/{APIFY_TURO_ACTOR_ID}/runs?token={apify_token}"

        # Extract just city name (e.g., "ATL Atlanta" -> "atlanta")
        city_parts = city_name.split()
        if len(city_parts) > 1:
            search_city = city_parts[1].lower()  # Take second part
        else:
            search_city = city_name.lower()

        run_input = {
            "location": search_city,
            "fromDate": pickup_datetime,
            "untilDate": return_datetime,
            "age": age,
            "sortBy": "daily_price_low_to_high",  # Must be exact value from allowed list
            "maxVehiclesReturn": 10  # Minimum allowed by API
        }

        print(f"    Starting Turo search for '{search_city}'...")
        print(f"    Input: {run_input}")
        response = requests.post(run_url, json=run_input, timeout=30)

        if response.status_code != 201:
            print(f"    Error response: {response.text}")
        response.raise_for_status()

        run_data = response.json()
        run_id = run_data['data']['id']
        print(f"    Run ID: {run_id}")

        # Wait for the run to complete - check status instead of just waiting
        status_url = f"{APIFY_API_BASE}/actor-runs/{run_id}?token={apify_token}"
        dataset_url = f"{APIFY_API_BASE}/actor-runs/{run_id}/dataset/items?token={apify_token}"

        max_wait = 90  # 90 seconds max wait (scraper takes ~40s)
        wait_time = 0

        while wait_time < max_wait:
            time.sleep(3)
            wait_time += 3

            # Check run status
            status_response = requests.get(status_url, timeout=30)
            if status_response.status_code == 200:
                status_data = status_response.json()
                run_status = status_data['data']['status']
                print(f"    Status at {wait_time}s: {run_status}")

                if run_status == 'SUCCEEDED':
                    # Get the dataset
                    print(f"    Fetching dataset...")
                    results_response = requests.get(dataset_url, timeout=30)
                    print(f"    Dataset response status: {results_response.status_code}")

                    if results_response.status_code == 200:
                        vehicles = results_response.json()
                        print(f"    Found {len(vehicles) if vehicles else 0} vehicles")

                        if vehicles and len(vehicles) > 0:
                            # Get lowest avgDailyPrice (already sorted by API)
                            # Price is a dict: {'amount': 29.7, 'currency': 'USD'}
                            vehicle = vehicles[0]
                            price_data = vehicle.get('avgDailyPrice')
                            if price_data and isinstance(price_data, dict):
                                lowest_price = price_data.get('amount')
                                vehicle_url = vehicle.get('url') or vehicle.get('vehicleUrl')
                                if lowest_price:
                                    print(f"    Turo: ${lowest_price:.2f} (lowest of {len(vehicles)} vehicles)")
                                    return {
                                        'price': lowest_price,
                                        'url': vehicle_url,
                                        'vehicle': f"{vehicle.get('year', '')} {vehicle.get('make', '')} {vehicle.get('model', '')}".strip()
                                    }
                    break
                elif run_status in ['FAILED', 'ABORTED', 'TIMED-OUT']:
                    print(f"    Turo run {run_status}")
                    return None

        print(f"    Turo search timed out after {wait_time}s")
        return None

    except Exception as e:
        print(f"    Error fetching Turo pricing: {e}")
        return None


# ============================================================================
# MAIN PROCESSING
# ============================================================================

def initialize_spreadsheet(input_file='CLT_Same_Day_Trips_UPDATED.xlsx'):
    """
    Load spreadsheet and ensure all pricing columns exist.
    """
    df = pd.read_excel(input_file)

    # Define all pricing columns
    pricing_columns = {
        # Cash pricing (Amadeus)
        'Cash Price Outbound': None,
        'Cash Price Return': None,
        'Cash Total Cost': None,

        # Award pricing (AA)
        'Award Miles Outbound Main': None,
        'Award Miles Outbound First': None,
        'Award Miles Return Main': None,
        'Award Miles Return First': None,

        # Car rental (Turo via Apify)
        'Turo Lowest Price': None,
        'Turo Vehicle': None,
        'Turo URL': None,

        # Metadata
        'Last Updated': None,
        'Pricing Date': None,
        'Pricing Status': None
    }

    # Add missing columns
    for col, default_value in pricing_columns.items():
        if col not in df.columns:
            df[col] = default_value

    return df


def update_pricing_for_trip(df, idx, search_date, amadeus_token, award_driver, apify_token, skip_cash, skip_awards, skip_turo):
    """Update all pricing for a single trip."""
    row = df.iloc[idx]
    destination = row['Destination']
    city_name = row['City']

    # Get departure times from spreadsheet
    depart_clt = str(row['Depart CLT'])  # e.g., "05:30"
    depart_dest = str(row['Depart Destination'])  # e.g., "17:14"
    arrive_dest = str(row.get('Arrive Destination', ''))  # e.g., "06:48"
    depart_dest_time = str(row['Depart Destination'])  # e.g., "17:14"

    print(f"\n[{idx+1}/{len(df)}] {destination} - {city_name}")
    print(f"  Flight times: Depart CLT {depart_clt}, Depart {destination} {depart_dest}")

    updates = {}
    status_parts = []

    # ========== CASH PRICING ==========
    if not skip_cash:
        print("  [Cash] Fetching Amadeus prices...")
        print(f"    Looking for outbound ~{depart_clt}, return ~{depart_dest}")

        # Outbound: CLT -> Destination (match departure time from spreadsheet)
        cash_out = fetch_cash_pricing(amadeus_token, 'CLT', destination, search_date, depart_clt)
        if cash_out:
            updates['Cash Price Outbound'] = cash_out
            print(f"    Outbound: ${cash_out:.2f}")
        else:
            print(f"    Outbound: Not found matching {depart_clt}")

        time.sleep(1)

        # Return: Destination -> CLT (match departure time from spreadsheet)
        cash_ret = fetch_cash_pricing(amadeus_token, destination, 'CLT', search_date, depart_dest)
        if cash_ret:
            updates['Cash Price Return'] = cash_ret
            print(f"    Return: ${cash_ret:.2f}")
        else:
            print(f"    Return: Not found matching {depart_dest}")

        # Calculate total
        if cash_out and cash_ret:
            updates['Cash Total Cost'] = cash_out + cash_ret
            status_parts.append('Cash OK')
            print(f"    Total: ${cash_out + cash_ret:.2f}")
        else:
            status_parts.append('Cash Partial' if (cash_out or cash_ret) else 'Cash Failed')

    # ========== AWARD PRICING ==========
    if not skip_awards:
        print("  [Award] Fetching AA miles...")

        # Outbound: CLT -> Destination
        award_out = fetch_award_pricing(award_driver, 'CLT', destination, search_date, depart_clt)
        if award_out:
            updates['Award Miles Outbound Main'] = award_out['main']
            updates['Award Miles Outbound First'] = award_out['first']
            print(f"    Outbound: {award_out['main']}K Main / {award_out['first']}K First")
        else:
            updates['Award Miles Outbound Main'] = 'No Reward Available'
            updates['Award Miles Outbound First'] = 'No Reward Available'
            print(f"    Outbound: No reward availability")

        time.sleep(2)

        # Return: Destination -> CLT
        award_ret = fetch_award_pricing(award_driver, destination, 'CLT', search_date, depart_dest)
        if award_ret:
            updates['Award Miles Return Main'] = award_ret['main']
            updates['Award Miles Return First'] = award_ret['first']
            print(f"    Return: {award_ret['main']}K Main / {award_ret['first']}K First")
        else:
            updates['Award Miles Return Main'] = 'No Reward Available'
            updates['Award Miles Return First'] = 'No Reward Available'
            print(f"    Return: No reward availability")

        # Status
        if award_out and award_ret:
            status_parts.append('Award OK')
        elif award_out or award_ret:
            status_parts.append('Award Partial')
        else:
            status_parts.append('Award: No availability')

    # ========== TURO CAR RENTAL PRICING ==========
    if not skip_turo and apify_token:
        print("  [Turo] Fetching rental car prices...")

        # Calculate pickup/return times based on flight arrival/departure
        # Pickup: When arriving at destination (use arrive_dest if available)
        # Return: When departing from destination
        try:
            # Parse dates and times
            if arrive_dest and arrive_dest != 'nan':
                pickup_time = arrive_dest
            else:
                # Estimate arrival ~1-2 hours after CLT departure
                pickup_time = "10:00"  # Default fallback

            # Format datetime as YYYY-MM-DDTHH:MM (not HH:MM:SS)
            pickup_datetime = f"{search_date}T{pickup_time}"
            return_datetime = f"{search_date}T{depart_dest}"

            turo_result = fetch_turo_pricing(apify_token, city_name, pickup_datetime, return_datetime)

            if turo_result:
                if isinstance(turo_result, dict):
                    updates['Turo Lowest Price'] = turo_result.get('price')
                    updates['Turo Vehicle'] = turo_result.get('vehicle')
                    updates['Turo URL'] = turo_result.get('url')
                else:
                    # Backwards compatibility if it returns just a price
                    updates['Turo Lowest Price'] = turo_result
                status_parts.append('Turo OK')
            else:
                status_parts.append('Turo Failed')

        except Exception as e:
            print(f"    Error with Turo: {e}")
            status_parts.append('Turo Error')

    # Update metadata
    updates['Last Updated'] = datetime.now().strftime('%Y-%m-%d %H:%M')
    updates['Pricing Date'] = search_date
    updates['Pricing Status'] = ' | '.join(status_parts) if status_parts else 'No updates'

    # Apply updates to dataframe
    for col, value in updates.items():
        df.at[idx, col] = value

    return df


def main():
    parser = argparse.ArgumentParser(description='Update all pricing for CLT same-day trips')
    parser.add_argument('--date', required=True, help='Travel date (YYYY-MM-DD)')
    parser.add_argument('--input', default='CLT_Same_Day_Trips_UPDATED.xlsx', help='Input spreadsheet')
    parser.add_argument('--output', default='CLT_Same_Day_Trips_With_Pricing.xlsx', help='Output spreadsheet')
    parser.add_argument('--skip-cash', action='store_true', help='Skip Amadeus cash pricing')
    parser.add_argument('--skip-awards', action='store_true', help='Skip AA award pricing')
    parser.add_argument('--skip-turo', action='store_true', help='Skip Turo car rental pricing')
    parser.add_argument('--apify-token', help='Apify API token for Turo pricing')
    parser.add_argument('--limit', type=int, help='Limit to N destinations (for testing)')
    parser.add_argument('--destination', help='Update only this destination (e.g., ATL, MIA)')
    parser.add_argument('--destinations', nargs='+', help='Update only these destinations (e.g., ATL MIA BOS)')
    args = parser.parse_args()

    print("=" * 70)
    print("CLT SAME-DAY TRIP PRICING UPDATER")
    print("=" * 70)
    print(f"Travel Date: {args.date}")
    print(f"Input: {args.input}")
    print(f"Output: {args.output}")
    print(f"Updates: Cash={not args.skip_cash}, Awards={not args.skip_awards}, Turo={not args.skip_turo and args.apify_token is not None}")
    print("=" * 70)

    # Load spreadsheet
    print(f"\nLoading {args.input}...")
    df = initialize_spreadsheet(args.input)
    total_destinations = len(df)
    print(f"Found {total_destinations} destinations")

    # Filter by destination(s) if specified
    if args.destination:
        df = df[df['Destination'] == args.destination.upper()].copy()
        if len(df) == 0:
            print(f"ERROR: Destination '{args.destination}' not found in spreadsheet")
            return
        print(f"FILTERING to single destination: {args.destination}")

    elif args.destinations:
        dest_list = [d.upper() for d in args.destinations]
        df = df[df['Destination'].isin(dest_list)].copy()
        if len(df) == 0:
            print(f"ERROR: None of the destinations {dest_list} found in spreadsheet")
            return
        print(f"FILTERING to destinations: {', '.join(dest_list)}")

    elif args.limit:
        df = df.head(args.limit).copy()
        print(f"LIMITED to first {args.limit} destinations for testing")

    print(f"Will process {len(df)} destination(s)")

    # Initialize Amadeus token
    amadeus_token = None
    if not args.skip_cash:
        print("\nAuthenticating with Amadeus API...")
        amadeus_token = get_amadeus_token()
        print("[SUCCESS] Amadeus authenticated")

    # Initialize browser for awards
    award_driver = None
    if not args.skip_awards:
        print("\nStarting browser for AA award search...")
        print("  (This may take 30-60 seconds on first launch...)")
        options = uc.ChromeOptions()
        options.add_argument('--no-sandbox')
        options.add_argument('--disable-dev-shm-usage')
        # Headless mode is faster but may get blocked - test both
        # options.add_argument('--headless=new')

        # Use our existing chromedriver
        award_driver = uc.Chrome(
            options=options,
            driver_executable_path='./chromedriver.exe',
            version_main=141
        )
        print("[SUCCESS] Browser started")
        time.sleep(1)

    # Process each destination
    print("\n" + "=" * 70)
    print("PROCESSING DESTINATIONS")
    print("=" * 70)

    # Reset index to avoid issues with filtered dataframes
    df = df.reset_index(drop=True)

    for idx in range(len(df)):
        try:
            df = update_pricing_for_trip(
                df, idx, args.date,
                amadeus_token, award_driver, args.apify_token,
                args.skip_cash, args.skip_awards, args.skip_turo
            )

            # Save progress after each destination
            df.to_excel(args.output, index=False)
            print(f"  [SAVED] Progress saved to {args.output}")

            # Delay between destinations
            time.sleep(3)

        except Exception as e:
            print(f"  [ERROR] {e}")
            df.at[idx, 'Pricing Status'] = f'Error: {str(e)[:50]}'
            continue

    # Cleanup
    if award_driver:
        award_driver.quit()

    # Final save
    df.to_excel(args.output, index=False)

    print("\n" + "=" * 70)
    print("COMPLETE!")
    print(f"Results saved to: {args.output}")
    print("=" * 70)


if __name__ == "__main__":
    main()
