"""
Script to search for AA award availablity for multiple origin/destination pairs
and dates. It lets you filter on departure time, duration, number of stops, 
and number of miles. 

At the time of writing, there were plenty of award search tools out there, but
AA just recently moved to dynamic pricing, so there weren't any that could 
filter on dynamic pricing.

This script uses Selenium to scrape the AA award search page. It's not the
fastest, but it works.

Usage:
    python search_aa_award_flights.py --help
"""

import argparse
import datetime
import itertools
import pandas as pd
import re
import time

from bs4 import BeautifulSoup
from pprint import pprint
import undetected_chromedriver as uc
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from typing import Any, Dict, List, Tuple
from tabulate import tabulate


def process_flights(flights: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    processed_flights = []

    for flight in flights:
        processed_flight = {}

        # Process origin, destination, depart_time, and arrive_time
        processed_flight["origin"] = flight["origin"]
        processed_flight["destination"] = flight["destination"]

        # Clean time strings - remove "+1" or other next-day indicators
        depart_time_str = flight["depart_time"].split("+")[0].strip()
        arrive_time_str = flight["arrive_time"].split("+")[0].strip()

        # Convert depart_time and arrive_time to datetime.time objects
        depart_time = datetime.datetime.strptime(
            depart_time_str, "%I:%M %p"
        ).time()
        arrive_time = datetime.datetime.strptime(
            arrive_time_str, "%I:%M %p"
        ).time()
        processed_flight["depart_time"] = depart_time
        processed_flight["arrive_time"] = arrive_time

        # Process duration
        duration_parts = re.findall(r"\d+", flight["duration"])
        duration_minutes = int(duration_parts[0]) * 60 + int(duration_parts[1])
        processed_flight["duration"] = duration_minutes

        # Process num_stops
        processed_flight["num_stops"] = int(flight["num_stops"].split(" ")[0])

        # Process miles
        num_miles = {}
        for cabin, miles in flight["num_miles"].items():
            cabin = cabin.lower()
            if "main" in cabin:
                cabin = "main"
            elif "first" in cabin:
                cabin = "first"
            elif "business" in cabin:
                cabin = "business"

            miles_value = float(miles.replace("K", ""))
            num_miles[cabin] = miles_value

        # Unpack to num_miles_X, where X is each key
        for cabin, miles in num_miles.items():
            processed_flight[f"num_miles_{cabin}"] = miles

        processed_flights.append(processed_flight)

    # sort by ascending depart_time
    processed_flights.sort(key=lambda x: x["depart_time"])

    return processed_flights


def scrape_flight_page(url: str, driver: uc.Chrome, sleep_sec: int = 10) -> list:
    """
    Scrapes the AA award flight page for flight details and number of miles for each cabin type.

    Args:
        url: URL of the AA award flight page to scrape.
        driver: Selenium webdriver to use to fetch the page.

    Returns:
        flights: List of dictionaries containing flight details and number of miles for each cabin type.
    """
    # fetch the page
    driver.get(url)

    print(f"[DEBUG] Waiting for flight results to load...")

    # Wait for either flight elements OR "no flights" message (up to 15 seconds)
    try:
        WebDriverWait(driver, 15).until(
            lambda d: len(d.find_elements(By.CSS_SELECTOR, "div[class*='flight']")) > 0
                   or "no flight" in d.page_source.lower()
                   or "sorry" in d.page_source.lower()
        )
        print(f"[DEBUG] Page loaded, extracting flight data...")
    except:
        print(f"[DEBUG] Timeout waiting for flights, proceeding anyway...")

    # Additional wait for JavaScript to settle
    if sleep_sec:
        time.sleep(sleep_sec)

    # get the page source
    html = driver.page_source

    # in the html, scrape flights
    soup = BeautifulSoup(html, "html.parser")

    # Debug: Save HTML to file for inspection
    print(f"[DEBUG] Saving page HTML to debug_page.html")
    with open("debug_page.html", "w", encoding="utf-8") as f:
        f.write(html)

    # Find all flight containers (new AA.com structure)
    # Each flight is in a div with class "grid-x grid-padding-x" that contains flight details
    results_container = soup.find("div", class_="results-grid-container")

    print(f"[DEBUG] Page title: {soup.title.string if soup.title else 'No title'}")
    print(f"[DEBUG] Page length: {len(html)} characters")

    if not results_container:
        print("[DEBUG] Could not find results-grid-container")
        return []

    # Find all app-slice-info-desktop elements (these contain flight info)
    flight_elements = results_container.find_all("app-slice-info-desktop")

    print(f"[DEBUG] Looking for flights with app-slice-info-desktop")
    print(f"[DEBUG] Found {len(flight_elements)} flight elements")

    # Initialize an empty list to store flight details
    flights = []

    # Iterate through each flight element and extract necessary information
    print(f"Found {len(flight_elements)} flights")
    for flight in flight_elements:
        # Extract origin, destination, depart_time, arrive_time, duration and num_stops
        try:
            origin_elem = flight.find("div", class_="origin")
            origin = origin_elem.find("div", class_="city-code").text.strip()
            depart_time = origin_elem.find("div", class_="flt-times").text.strip()

            dest_elem = flight.find("div", class_="destination")
            destination = dest_elem.find("div", class_="city-code").text.strip()
            arrive_time = dest_elem.find("div", class_="flt-times").text.strip()

            duration = flight.find("div", class_="duration").text.strip()

            # Check for nonstop or stops
            stops_elem = flight.find("app-stops-tooltip")
            if stops_elem:
                stops_text = stops_elem.text.strip()
                if "Nonstop" in stops_text:
                    num_stops = "0 stops"
                else:
                    num_stops = stops_text
            else:
                num_stops = "Unknown"

        except Exception as e:
            print(f"[DEBUG] Error parsing flight info: {e}")
            continue

        # Find award pricing - look in the parent container for app-available-products-desktop
        parent_row = flight.find_parent("div", class_="grid-x grid-padding-x")
        if not parent_row:
            print(f"[DEBUG] Could not find parent row for flight")
            continue

        products_container = parent_row.find("app-available-products-desktop")
        if not products_container:
            print(f"[DEBUG] Could not find products container")
            continue

        # Initialize an empty dictionary to store cabin type and corresponding number of miles
        cabin_miles = {}

        # Find all cabin pricing buttons
        cabin_buttons = products_container.find_all("button", class_="btn-flight")

        for cabin_button in cabin_buttons:
            cabin_type_elem = cabin_button.find("span", class_="hidden-product-type")
            miles_elem = cabin_button.find("span", class_="per-pax-amount")

            # If both a cabin type and number of miles are found, add them to the dictionary
            if cabin_type_elem and miles_elem:
                cabin_miles[cabin_type_elem.text.strip()] = miles_elem.text.strip()

        # Append this flight's details and number of miles for each cabin type to the list of flights
        flights.append(
            {
                "origin": origin,
                "destination": destination,
                "depart_time": depart_time,
                "arrive_time": arrive_time,
                "duration": duration,
                "num_stops": num_stops,
                "num_miles": cabin_miles,
            }
        )

    # Cleanup
    flights = process_flights(flights)

    return flights


def filter_flights(
    flights: List[Dict[str, Any]],
    max_miles_main: int,
    max_duration: int,
    depart_time_range: Tuple[datetime.time, datetime.time],
    arrive_time_range: Tuple[datetime.time, datetime.time],
    max_stops: int,
) -> List[Dict[str, Any]]:
    """
    Filters a list of flights based on various criteria.

    Args:
        flights: List of dictionaries containing flight details and number of miles for each cabin type.
        max_miles_main: Maximum number of miles allowed for a flight in the main cabin.
        max_duration: Maximum duration of a flight in minutes.
        depart_time_range: Tuple of minimum and maximum departure times allowed for a flight.
        arrive_time_range: Tuple of minimum and maximum arrival times allowed for a flight.
        max_stops: Maximum number of stops allowed for a flight.

    Returns:
        filtered_flights: List of dictionaries containing flight details and number of miles for each cabin type that meet the filtering criteria.
    """
    filtered_flights = []

    # fix times
    min_depart_time, max_depart_time = depart_time_range
    min_arrive_time, max_arrive_time = arrive_time_range

    for flight in flights:
        num_miles_main = flight.get("num_miles_main", 10000000)
        if (
            num_miles_main <= max_miles_main
            and flight["duration"] <= max_duration
            and flight["depart_time"] >= min_depart_time
            and flight["depart_time"] <= max_depart_time
            and flight["arrive_time"] >= min_arrive_time
            and flight["arrive_time"] <= max_arrive_time
            and flight["num_stops"] <= max_stops
        ):
            filtered_flights.append(flight)

    return filtered_flights


def generate_url(
    depart_date: str,
    origin: str,
    destination: str,
    n_adults: int,
    n_children: int,
) -> str:
    """
    Generates the URL for the AA award flight page.

    Args:
        depart_date: Departure date in YYYY-MM-DD format.
        origin: Origin airport code.
        destination: Destination airport code.
        n_adults: Number of adults.
        n_children: Number of children.

    Returns:
        url: URL of the AA award flight page to scrape.

    """
    n_passengers = n_adults + n_children
    url = f"https://www.aa.com/booking/search?locale=en_US&pax={n_passengers}&adult={n_adults}&child={n_children}&type=OneWay&searchType=Award&cabin=&carriers=ALL&slices=%5B%7B%22orig%22:%22{origin}%22,%22origNearby%22:false,%22dest%22:%22{destination}%22,%22destNearby%22:false,%22date%22:%22{depart_date}%22%7D%5D&maxAwardSegmentAllowed=2"
    return url


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Search for AA award availability for multiple origin/destination pairs and dates."
    )
    parser.add_argument(
        "-d",
        "--depart_date",
        nargs="+",
        help="Departure date(s) in YYYY-MM-DD format.",
        required=True,
    )
    parser.add_argument(
        "-o", "--origin", nargs="+", help="Origin airport codes.", required=True
    )
    parser.add_argument(
        "-des",
        "--destination",
        nargs="+",
        help="Destination airport codes.",
        required=True,
    )
    parser.add_argument("--n_adults", type=int, help="Number of adults.", default=1)
    parser.add_argument("--n_children", type=int, help="Number of children.", default=0)
    parser.add_argument(
        "--max_miles_main",
        type=int,
        default=20,
        help="Maximum number of miles in thousands.",
    )
    parser.add_argument(
        "--max_duration",
        type=int,
        default=11 * 60,
        help="Maximum duration of flight in minutes.",
    )
    parser.add_argument(
        "--depart_time_range",
        nargs=2,
        default=["07:00", "16:00"],
        help="Departure time range in HH:MM format.",
    )
    parser.add_argument(
        "--arrive_time_range",
        nargs=2,
        default=["12:00", "22:00"],
        help="Arrival time range in HH:MM format.",
    )
    parser.add_argument(
        "--max_stops", type=int, default=1, help="Maximum number of stops."
    )
    parser.add_argument(
        "--output_file_raw",
        default="flights_all.csv",
        help="Output file for raw flight data.",
    )
    parser.add_argument(
        "--output_file_filtered",
        default="flights_filtered.csv",
        help="Output file for filtered flight data.",
    )
    parser.add_argument(
        "--sleep_init_sec",
        type=int,
        default=10,
        help="Initial sleep time in seconds when loading browser.",
    )
    parser.add_argument(
        "--sleep_sec",
        type=int,
        default=5,
        help="Sleep time in seconds between each page load.",
    )
    args = parser.parse_args()
    print("Arguments:")
    pprint(vars(args))

    # Flight info
    depart_date = args.depart_date
    origin = args.origin
    destination = args.destination
    n_adults = args.n_adults
    n_children = args.n_children

    # Filter criteria
    max_miles_main = args.max_miles_main  # in thousands
    max_duration = args.max_duration  # in minutes
    depart_time_range = tuple(
        datetime.datetime.strptime(d, "%H:%M").time() for d in args.depart_time_range
    )
    arrive_time_range = tuple(
        datetime.datetime.strptime(d, "%H:%M").time() for d in args.arrive_time_range
    )
    max_stops = args.max_stops

    # Other config
    output_file_raw = args.output_file_raw
    output_file_filtered = args.output_file_filtered
    sleep_init_sec = args.sleep_init_sec
    sleep_sec = args.sleep_sec

    # use undetected-chromedriver to bypass bot detection
    options = uc.ChromeOptions()
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')

    print("Starting undetected Chrome driver...")
    driver = uc.Chrome(options=options, version_main=141)
    print("Undetected Chrome driver started successfully")
    time.sleep(sleep_init_sec)

    # loop through all of depart_date, origin, and destination combos.. including a counter
    all_flights = []
    all_filtered_flights = []
    error_combos = []
    missing_combos = []
    for i, (dt, o, d) in enumerate(itertools.product(depart_date, origin, destination)):
        # print the current iteration out of total iterations to keep track of progress
        print(
            f"\nScraping {i+1} of {len(depart_date) * len(origin) * len(destination)}: {dt}, {o}, {d}"
        )

        # generate the url
        url = generate_url(
            dt,
            o,
            d,
            n_adults,
            n_children,
        )

        # scrape the flights
        flights = []
        filtered_flights = []
        try:
            flights = scrape_flight_page(url, driver, sleep_sec=sleep_sec)
        except Exception as e:
            print(f"Error scraping: {e}")
            import traceback
            traceback.print_exc()
            error_combos.append((dt, o, d))
            continue
        print(f"Found {len(flights)} total flights.")

        if len(flights) == 0:
            print("No flights found. Continuing to next iteration.")
            missing_combos.append((dt, o, d))
            continue

        # add the date to each object
        for flight in flights:
            flight["date"] = dt

        # filter the flights
        if len(flights) > 0:
            filtered_flights = filter_flights(
                flights,
                max_miles_main,
                max_duration,
                depart_time_range,
                arrive_time_range,
                max_stops,
            )
            print(f"Found {len(filtered_flights)} flights that meet the criteria.")

            all_flights.extend(flights)

        if len(filtered_flights) > 0:
            all_filtered_flights.extend(filtered_flights)

    print("Done scraping.")
    print(f"Found {len(all_flights)} total flights.")
    print(f"Found {len(all_filtered_flights)} flights that meet the criteria.")

    # Sort all by ascending origin, then ascending date, then ascending time
    all_filtered_flights = sorted(
        all_filtered_flights, key=lambda x: (x["origin"], x["date"], x["depart_time"])
    )

    # print in a pretty table
    print(
        tabulate(
            all_filtered_flights,
            headers="keys",
            tablefmt="pretty",
            showindex="never",
            floatfmt=".2f",
        )
    )

    # Save to CSV
    if len(all_filtered_flights) > 0:
        df = pd.DataFrame(all_filtered_flights)
        df.to_csv(output_file_filtered, index=False)
        print(f"Saved {len(all_filtered_flights)} records to {output_file_filtered}.")
    if len(all_flights) > 0:
        df = pd.DataFrame(all_flights)
        df.to_csv(output_file_raw, index=False)
        print(f"Saved {len(all_flights)} records to {output_file_raw}.")

    # print errors
    if len(error_combos) > 0:
        print("\nErrors:")
        pprint(error_combos)

    if len(missing_combos) > 0:
        print("\nMissing:")
        pprint(missing_combos)
