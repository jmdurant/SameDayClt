"""
CLT Same-Day Trip Pricer - Amadeus API Integration
===================================================

This script fetches real-time flight prices for same-day trips from Charlotte (CLT)
using the Amadeus Flight API.

SETUP:
1. Ensure you have: pip install requests pandas openpyxl python-dateutil
2. Update the spreadsheet path if needed
3. Run: python clt_price_fetcher.py

Author: Created for CLT Same-Day Trip Planner Project
Date: October 2025
"""

import requests
import pandas as pd
from datetime import datetime, timedelta
import time
import json

# ============================================================================
# CONFIGURATION
# ============================================================================

# Amadeus API Credentials
AMADEUS_API_KEY = "zDYWXqUHNcmVPjvHVxBeTLK8pZGZ8KbI"
AMADEUS_API_SECRET = "QcuIX7JOc4G0AOdc"

# API Endpoints
AUTH_URL = "https://test.api.amadeus.com/v1/security/oauth2/token"
FLIGHT_SEARCH_URL = "https://test.api.amadeus.com/v2/shopping/flight-offers"

# File paths
INPUT_FILE = "CLT_Same_Day_Trips_UPDATED.xlsx"
OUTPUT_FILE = "CLT_Trips_With_Real_Prices.xlsx"

# Search parameters
SEARCH_DATES = 7  # Number of days ahead to search
DELAY_BETWEEN_CALLS = 0.5  # Seconds to wait between API calls (be nice to the API)

# ============================================================================
# AMADEUS API FUNCTIONS
# ============================================================================

def get_access_token():
    """
    Authenticate with Amadeus API and get access token.

    Returns:
        str: Access token for API calls
    """
    print("Authenticating with Amadeus API...")

    auth_data = {
        "grant_type": "client_credentials",
        "client_id": AMADEUS_API_KEY,
        "client_secret": AMADEUS_API_SECRET
    }

    try:
        response = requests.post(AUTH_URL, data=auth_data, timeout=30)
        response.raise_for_status()

        token_data = response.json()
        access_token = token_data['access_token']
        expires_in = token_data.get('expires_in', 1800)

        print(f"[SUCCESS] Authentication successful! Token expires in {expires_in} seconds")
        return access_token

    except requests.exceptions.RequestException as e:
        print(f"[ERROR] Authentication failed: {e}")
        return None


def search_flights(access_token, origin, destination, departure_date, max_results=10):
    """
    Search for flights between two airports on a specific date.
    
    Args:
        access_token (str): Amadeus API access token
        origin (str): Origin airport code (e.g., 'CLT')
        destination (str): Destination airport code (e.g., 'ATL')
        departure_date (str): Date in YYYY-MM-DD format
        max_results (int): Maximum number of results to return
        
    Returns:
        list: Flight offers data
    """
    headers = {
        "Authorization": f"Bearer {access_token}"
    }
    
    params = {
        "originLocationCode": origin,
        "destinationLocationCode": destination,
        "departureDate": departure_date,
        "adults": 1,
        "max": max_results,
        "currencyCode": "USD"
    }
    
    try:
        response = requests.get(FLIGHT_SEARCH_URL, headers=headers, params=params, timeout=30)
        response.raise_for_status()

        data = response.json()

        if 'data' in data and len(data['data']) > 0:
            return data['data']
        else:
            return []

    except requests.exceptions.RequestException as e:
        print(f"  [WARNING] Search failed for {origin}->{destination}: {e}")
        return []


def filter_morning_flights(flights):
    """
    Filter flights to only include those departing before 10 AM.

    Args:
        flights (list): List of flight offers

    Returns:
        list: Filtered flights with morning departures
    """
    morning_flights = []

    for flight in flights:
        # Get departure time from first segment
        departure_time = flight['itineraries'][0]['segments'][0]['departure']['at']
        departure_dt = datetime.fromisoformat(departure_time.replace('Z', '+00:00'))

        # Check if departure is before 10 AM (allows 9:00 departures)
        if departure_dt.hour < 10:
            morning_flights.append(flight)

    return morning_flights


def filter_evening_arrivals(flights):
    """
    Filter flights to only include those arriving between 3 PM - 7 PM (allows up to 18:59).

    Args:
        flights (list): List of flight offers

    Returns:
        list: Filtered flights with evening arrivals
    """
    evening_flights = []

    for flight in flights:
        # Get arrival time from last segment
        arrival_time = flight['itineraries'][0]['segments'][-1]['arrival']['at']
        arrival_dt = datetime.fromisoformat(arrival_time.replace('Z', '+00:00'))

        # Check if arrival is between 3 PM - 7 PM (15:00-18:59)
        # This matches flights arriving at 15:18, 16:26, 17:22, 18:45, etc.
        if 15 <= arrival_dt.hour <= 18:
            evening_flights.append(flight)

    return evening_flights


def get_cheapest_price(flights):
    """
    Get the cheapest price from a list of flights.
    
    Args:
        flights (list): List of flight offers
        
    Returns:
        float: Cheapest price, or None if no flights
    """
    if not flights:
        return None
    
    prices = [float(flight['price']['total']) for flight in flights]
    return min(prices) if prices else None


# ============================================================================
# MAIN PROCESSING
# ============================================================================

def main():
    """
    Main function to process all destinations and fetch real prices.
    """
    print("=" * 80)
    print("CLT SAME-DAY TRIP REAL PRICING FETCHER")
    print("=" * 80)
    print()

    # Step 1: Authenticate
    access_token = get_access_token()
    if not access_token:
        print("[ERROR] Cannot proceed without authentication. Exiting.")
        return
    
    print()
    
    # Step 2: Load destination data
    print(f"Loading destinations from {INPUT_FILE}...")
    try:
        df = pd.read_excel(INPUT_FILE, sheet_name='Best Same-Day Trips')
        print(f"[SUCCESS] Loaded {len(df)} destinations")
    except Exception as e:
        print(f"[ERROR] Failed to load spreadsheet: {e}")
        return

    print()

    # Step 3: Prepare for price fetching
    search_date = (datetime.now() + timedelta(days=SEARCH_DATES)).strftime('%Y-%m-%d')
    print(f"Searching for flights on: {search_date}")
    print(f"Processing {len(df)} destinations...")
    print()
    
    # Add columns for real prices
    df['Real Flight Price Outbound'] = None
    df['Real Flight Price Return'] = None
    df['Real Total Flight Cost'] = None
    df['Price Fetch Date'] = search_date
    df['Price Fetch Status'] = 'Pending'
    
    # Step 4: Fetch prices for each destination
    for idx, row in df.iterrows():
        destination = row['Destination']
        city = row['City']
        
        print(f"[{idx+1}/{len(df)}] Fetching prices for {destination} ({city})...")
        
        try:
            # Search outbound flights (CLT -> Destination)
            print(f"  Searching outbound (CLT -> {destination})...")
            outbound_flights = search_flights(access_token, 'CLT', destination, search_date)
            outbound_morning = filter_morning_flights(outbound_flights)
            outbound_price = get_cheapest_price(outbound_morning)

            time.sleep(DELAY_BETWEEN_CALLS)

            # Search return flights (Destination -> CLT)
            print(f"  Searching return ({destination} -> CLT)...")
            return_flights = search_flights(access_token, destination, 'CLT', search_date)
            return_evening = filter_evening_arrivals(return_flights)
            return_price = get_cheapest_price(return_evening)
            
            # Update dataframe
            if outbound_price and return_price:
                df.at[idx, 'Real Flight Price Outbound'] = outbound_price
                df.at[idx, 'Real Flight Price Return'] = return_price
                df.at[idx, 'Real Total Flight Cost'] = outbound_price + return_price
                df.at[idx, 'Price Fetch Status'] = 'Success'
                print(f"  [SUCCESS] Prices found: ${outbound_price:.2f} + ${return_price:.2f} = ${outbound_price + return_price:.2f}")
            else:
                df.at[idx, 'Price Fetch Status'] = 'No flights found'
                print(f"  [WARNING] No suitable flights found")

            time.sleep(DELAY_BETWEEN_CALLS)

        except Exception as e:
            print(f"  [ERROR] Error processing {destination}: {e}")
            df.at[idx, 'Price Fetch Status'] = f'Error: {str(e)[:50]}'

        print()
    
    # Step 5: Save results
    print("=" * 80)
    print("Saving results...")

    try:
        df.to_excel(OUTPUT_FILE, index=False, sheet_name='Trips with Real Prices')
        print(f"[SUCCESS] Results saved to: {OUTPUT_FILE}")

        # Print summary
        successful = len(df[df['Price Fetch Status'] == 'Success'])
        print()
        print("SUMMARY:")
        print(f"  Total destinations: {len(df)}")
        print(f"  Successful price fetches: {successful}")
        print(f"  Failed/No flights: {len(df) - successful}")

        if successful > 0:
            avg_price = df['Real Total Flight Cost'].mean()
            min_price = df['Real Total Flight Cost'].min()
            max_price = df['Real Total Flight Cost'].max()

            print()
            print(f"  Average flight cost: ${avg_price:.2f}")
            print(f"  Cheapest flight: ${min_price:.2f}")
            print(f"  Most expensive: ${max_price:.2f}")

    except Exception as e:
        print(f"[ERROR] Failed to save results: {e}")

    print()
    print("=" * 80)
    print("Done! Check the output file for real pricing data.")
    print("=" * 80)


# ============================================================================
# SCRIPT ENTRY POINT
# ============================================================================

if __name__ == "__main__":
    main()


# ============================================================================
# NOTES FOR CLAUDE CODE
# ============================================================================

"""
IMPORTANT NOTES:

1. This script searches for ONE-WAY flights separately (outbound and return).
   The Amadeus API doesn't have a great same-day round-trip search, so we
   search each direction and combine the prices.

2. Time filtering is approximate. The API returns all flights for a date,
   and we filter by departure/arrival hour. You may want to refine this
   to be more precise (e.g., 5:00-8:59 AM for departures).

3. API rate limits: Free tier = 2000 calls/month. This script uses ~2 calls
   per destination = ~84 calls total. You have plenty of headroom.

4. Prices are for ONE date (7 days from now by default). To find the cheapest
   date, you'd need to search multiple dates (multiply API calls).

5. Error handling: The script continues even if some destinations fail.
   Check the 'Price Fetch Status' column in the output.

ENHANCEMENTS YOU COULD ADD:

- Search multiple dates and find cheapest
- Add car rental pricing (Turo/RapidAPI integration)
- Create visualizations of price data
- Set up automated daily price checks
- Add price drop alerts
- Store historical prices in database
- Calculate cost per hour with real prices

TROUBLESHOOTING:

- If authentication fails, verify your API keys are correct
- If no flights found, try expanding the time windows
- If getting 429 errors, add more delay between calls
- Check Amadeus dashboard for API usage stats
"""