"""
Test script to verify Turo pricing integration via Apify.

This tests the Turo car rental pricing functionality that was added to
update_all_pricing.py to ensure it works correctly.

Usage:
    python test_turo_pricing.py
    python test_turo_pricing.py --apify-token YOUR_TOKEN
"""

import argparse
import requests
import time
from datetime import datetime, timedelta


APIFY_TURO_ACTOR_ID = "MrlcWebEaPAMtKAas"
APIFY_API_BASE = "https://api.apify.com/v2"


def test_turo_pricing(apify_token, city_name="atlanta", test_date=None):
    """
    Test Turo pricing fetch for a single city.

    Args:
        apify_token: Apify API token
        city_name: City name to search (default: "atlanta")
        test_date: Date to search (default: 7 days from now)
    """
    if not apify_token:
        print("ERROR: Apify token is required")
        print("Get your token from: https://console.apify.com/account/integrations")
        print("Usage: python test_turo_pricing.py --apify-token YOUR_TOKEN")
        return False

    if not test_date:
        test_date = (datetime.now() + timedelta(days=7)).strftime('%Y-%m-%d')

    # Set pickup/return times for a typical same-day trip
    pickup_datetime = f"{test_date}T10:00"
    return_datetime = f"{test_date}T18:00"

    print("=" * 70)
    print("TURO PRICING TEST")
    print("=" * 70)
    print(f"City: {city_name}")
    print(f"Pickup: {pickup_datetime}")
    print(f"Return: {return_datetime}")
    print("=" * 70)

    try:
        # Start the Apify actor run
        run_url = f"{APIFY_API_BASE}/acts/{APIFY_TURO_ACTOR_ID}/runs?token={apify_token}"

        run_input = {
            "location": city_name.lower(),
            "fromDate": pickup_datetime,
            "untilDate": return_datetime,
            "age": 25,
            "sortBy": "daily_price_low_to_high",
            "maxVehiclesReturn": 10  # Minimum allowed by API
        }

        print("\n[1] Starting Apify actor run...")
        print(f"    Input: {run_input}")

        response = requests.post(run_url, json=run_input, timeout=30)

        if response.status_code != 201:
            print(f"\n[ERROR] Failed to start run")
            print(f"Status code: {response.status_code}")
            print(f"Response: {response.text}")
            return False

        run_data = response.json()
        run_id = run_data['data']['id']
        print(f"    [OK] Run started successfully! Run ID: {run_id}")

        # Wait for the run to complete
        status_url = f"{APIFY_API_BASE}/actor-runs/{run_id}?token={apify_token}"
        dataset_url = f"{APIFY_API_BASE}/actor-runs/{run_id}/dataset/items?token={apify_token}"

        print("\n[2] Waiting for scraper to complete...")
        print("    (This typically takes 40-60 seconds)")

        max_wait = 90
        wait_time = 0

        while wait_time < max_wait:
            time.sleep(5)
            wait_time += 5

            status_response = requests.get(status_url, timeout=30)
            if status_response.status_code == 200:
                status_data = status_response.json()
                run_status = status_data['data']['status']
                print(f"    [{wait_time}s] Status: {run_status}")

                if run_status == 'SUCCEEDED':
                    print("    [OK] Scraper completed successfully!")

                    # Get the dataset
                    print("\n[3] Fetching vehicle data...")
                    results_response = requests.get(dataset_url, timeout=30)

                    if results_response.status_code != 200:
                        print(f"    [ERROR] Failed to fetch dataset")
                        print(f"    Status code: {results_response.status_code}")
                        return False

                    vehicles = results_response.json()
                    print(f"    [OK] Found {len(vehicles) if vehicles else 0} vehicles")

                    if vehicles and len(vehicles) > 0:
                        print("\n" + "=" * 70)
                        print("RESULTS")
                        print("=" * 70)

                        # Show top 5 cheapest vehicles
                        for i, vehicle in enumerate(vehicles[:5], 1):
                            price_data = vehicle.get('avgDailyPrice', {})
                            price = price_data.get('amount', 'N/A')
                            currency = price_data.get('currency', 'USD')

                            make = vehicle.get('make', 'Unknown')
                            model = vehicle.get('model', 'Unknown')
                            year = vehicle.get('year', 'N/A')

                            print(f"\n{i}. {year} {make} {model}")
                            print(f"   Price: ${price:.2f} {currency}/day")
                            print(f"   Total: ${price * 1:.2f} (8-hour rental)")

                        # Get lowest price
                        lowest = vehicles[0].get('avgDailyPrice', {}).get('amount')
                        if lowest:
                            print("\n" + "=" * 70)
                            print(f"[SUCCESS] LOWEST PRICE: ${lowest:.2f}/day")
                            print("=" * 70)
                            return True
                        else:
                            print("\n[WARNING] Could not extract price from results")
                            return False
                    else:
                        print("\n[WARNING] No vehicles found for this search")
                        return False

                elif run_status in ['FAILED', 'ABORTED', 'TIMED-OUT']:
                    print(f"\n[ERROR] Scraper {run_status}")
                    return False

        print(f"\n[ERROR] Timed out after {wait_time}s")
        return False

    except Exception as e:
        print(f"\n[ERROR] Exception occurred: {e}")
        import traceback
        traceback.print_exc()
        return False


def main():
    parser = argparse.ArgumentParser(description='Test Turo pricing integration')
    parser.add_argument('--apify-token', help='Apify API token')
    parser.add_argument('--city', default='atlanta', help='City to search (default: atlanta)')
    parser.add_argument('--date', help='Date to search (YYYY-MM-DD, default: 7 days from now)')
    args = parser.parse_args()

    success = test_turo_pricing(args.apify_token, args.city, args.date)

    if success:
        print("\n[SUCCESS] Test PASSED - Turo integration is working!")
    else:
        print("\n[FAILED] Test FAILED - Check errors above")

    return 0 if success else 1


if __name__ == "__main__":
    exit(main())
