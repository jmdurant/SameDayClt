"""
Fetch AA award pricing for same-day trips and add to spreadsheet.

This script:
1. Reads CLT_Trips_With_Real_Prices.xlsx with cash pricing
2. Searches AA.com for award availability on specific flights/routes
3. Adds award pricing columns (outbound/return miles in Main/First)
4. Saves updated spreadsheet with both cash and award pricing
"""

import pandas as pd
import time
import sys
import os
from datetime import datetime, timedelta

# Add the aa_flight_search_tool directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'aa_flight_search_tool'))

from search_aa_award_flights import scrape_flight_page, generate_url
import undetected_chromedriver as uc


def find_matching_flight(flights, depart_time_target, max_time_diff_minutes=30):
    """
    Find flight closest to target departure time.

    Args:
        flights: List of flight dicts from scraper
        depart_time_target: Target departure time as string (e.g., "05:30")
        max_time_diff_minutes: Maximum difference in minutes to consider a match

    Returns:
        Flight dict or None if no match found
    """
    if not flights:
        return None

    # Parse target time
    target_hour, target_min = map(int, depart_time_target.split(':'))
    target_minutes = target_hour * 60 + target_min

    best_match = None
    best_diff = float('inf')

    for flight in flights:
        flight_time = flight['depart_time']
        flight_minutes = flight_time.hour * 60 + flight_time.minute

        diff = abs(flight_minutes - target_minutes)

        if diff < best_diff and diff <= max_time_diff_minutes:
            best_diff = diff
            best_match = flight

    return best_match


def fetch_award_pricing_for_route(driver, origin, destination, depart_date, target_depart_time, sleep_sec=8):
    """
    Fetch award pricing for a specific route and find flight matching target time.

    Returns:
        dict with award pricing info or None if not found
    """
    url = generate_url(
        depart_date=depart_date,
        origin=origin,
        destination=destination,
        n_adults=1,
        n_children=0
    )

    try:
        print(f"  Searching {origin}->{destination} departing ~{target_depart_time}")
        flights = scrape_flight_page(url, driver, sleep_sec=sleep_sec)

        if not flights:
            print(f"    No flights found")
            return None

        # Find flight closest to target departure time
        matching_flight = find_matching_flight(flights, target_depart_time)

        if not matching_flight:
            print(f"    No flight found near target time {target_depart_time}")
            return None

        print(f"    Found flight: {matching_flight['depart_time']} -> {matching_flight['arrive_time']}")
        print(f"    Main: {matching_flight.get('num_miles_main', 'N/A')}K, First: {matching_flight.get('num_miles_first', 'N/A')}K")

        return matching_flight

    except Exception as e:
        print(f"    Error fetching: {e}")
        return None


def main():
    # Read the spreadsheet with cash prices
    input_file = 'CLT_Trips_With_Real_Prices.xlsx'
    output_file = 'CLT_Trips_With_Award_Pricing.xlsx'

    print(f"Reading {input_file}...")
    df = pd.read_excel(input_file)

    print(f"Found {len(df)} trips")

    # Add new columns for award pricing
    df['Award Miles Outbound Main'] = None
    df['Award Miles Outbound First'] = None
    df['Award Miles Return Main'] = None
    df['Award Miles Return First'] = None
    df['Award Fetch Date'] = None
    df['Award Fetch Status'] = None

    # Start browser
    print("\nStarting undetected Chrome driver...")
    options = uc.ChromeOptions()
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    driver = uc.Chrome(options=options, version_main=141)
    print("Browser started successfully")
    time.sleep(2)

    # Use a sample date (7 days from now for testing)
    search_date = (datetime.now() + timedelta(days=7)).strftime('%Y-%m-%d')
    return_date = search_date  # Same day return

    print(f"\nSearching for award availability on {search_date}")
    print("=" * 60)

    successful = 0
    failed = 0

    for idx, row in df.iterrows():
        destination = row['Destination']
        depart_clt_time = row['Depart CLT']
        depart_dest_time = row['Depart Destination']

        print(f"\n[{idx+1}/{len(df)}] Processing {destination}...")

        try:
            # Fetch outbound award pricing (CLT -> Destination)
            outbound = fetch_award_pricing_for_route(
                driver, 'CLT', destination, search_date,
                depart_clt_time, sleep_sec=8
            )

            if outbound:
                df.at[idx, 'Award Miles Outbound Main'] = outbound.get('num_miles_main')
                df.at[idx, 'Award Miles Outbound First'] = outbound.get('num_miles_first')

            # Small delay between searches
            time.sleep(3)

            # Fetch return award pricing (Destination -> CLT)
            inbound = fetch_award_pricing_for_route(
                driver, destination, 'CLT', return_date,
                depart_dest_time, sleep_sec=8
            )

            if inbound:
                df.at[idx, 'Award Miles Return Main'] = inbound.get('num_miles_main')
                df.at[idx, 'Award Miles Return First'] = inbound.get('num_miles_first')

            # Update status
            if outbound or inbound:
                df.at[idx, 'Award Fetch Status'] = 'Partial' if (not outbound or not inbound) else 'Success'
                df.at[idx, 'Award Fetch Date'] = datetime.now().strftime('%Y-%m-%d %H:%M')
                successful += 1
            else:
                df.at[idx, 'Award Fetch Status'] = 'No flights found'
                failed += 1

            # Save progress after each destination
            df.to_excel(output_file, index=False)
            print(f"  Progress saved to {output_file}")

            # Small delay between destinations
            time.sleep(2)

        except Exception as e:
            print(f"  ERROR: {e}")
            df.at[idx, 'Award Fetch Status'] = f'Error: {str(e)[:50]}'
            failed += 1
            continue

    # Close browser
    driver.quit()

    # Final save
    df.to_excel(output_file, index=False)

    print("\n" + "=" * 60)
    print(f"COMPLETE!")
    print(f"Successful: {successful}, Failed: {failed}")
    print(f"Results saved to: {output_file}")


if __name__ == "__main__":
    main()
