"""
Generate data.js from Excel file with real Amadeus pricing data
This creates a JavaScript file that can be included in the HTML pages
"""

import pandas as pd
from datetime import datetime
import json

INPUT_FILE = "CLT_Trips_With_Real_Prices.xlsx"
OUTPUT_FILE = "trips_data.js"

def generate_data_js():
    """
    Read Excel file and generate JavaScript data file
    """
    print("=" * 80)
    print("CLT TRIP DATA.JS GENERATOR")
    print("=" * 80)
    print()

    # Read the Excel file
    print(f"Reading data from {INPUT_FILE}...")
    try:
        df = pd.read_excel(INPUT_FILE, sheet_name='Trips with Real Prices')
        print(f"[SUCCESS] Loaded {len(df)} destinations")
    except Exception as e:
        print(f"[ERROR] Failed to load Excel file: {e}")
        return

    print()

    # Build the trips array
    trips = []

    def parse_time_to_minutes(time_str):
        """Convert time string like '10h 26m' to minutes"""
        hours = 0
        minutes = 0
        if 'h' in time_str:
            parts = time_str.split('h')
            hours = int(parts[0].strip())
            if len(parts) > 1 and 'm' in parts[1]:
                minutes = int(parts[1].replace('m', '').strip())
        elif 'm' in time_str:
            minutes = int(time_str.replace('m', '').strip())
        return hours * 60 + minutes

    # Airport coordinates for map
    airport_coords = {
        'ATL': (33.6407, -84.4277), 'MIA': (25.7959, -80.2870), 'LGA': (40.7769, -73.8740),
        'JFK': (40.6413, -73.7781), 'ILM': (34.2706, -77.9026), 'CHS': (32.8986, -80.0405),
        'RIC': (37.5052, -77.3197), 'MYR': (33.6797, -78.9283), 'EWR': (40.6895, -74.1745),
        'ROA': (37.3255, -79.9754), 'ORD': (41.9742, -87.9073), 'TYS': (35.8111, -83.9940),
        'SAV': (32.1276, -81.2021), 'CHO': (38.1386, -78.4529), 'FAY': (34.9912, -78.8803),
        'FLL': (26.0742, -80.1506), 'ORF': (36.8946, -76.2012), 'IND': (39.7173, -86.2944),
        'CHA': (35.0353, -85.2038), 'TPA': (27.9755, -82.5332), 'PHL': (39.8719, -75.2411),
        'MDT': (40.1935, -76.7634), 'CLE': (41.4117, -81.8498), 'STL': (38.7487, -90.3700),
        'BNA': (36.1245, -86.6782), 'MCO': (28.4294, -81.3089), 'JAX': (30.4941, -81.6879),
        'MEM': (35.0424, -89.9767), 'TRI': (36.4752, -82.4074), 'GSO': (36.0978, -79.9373),
        'LYH': (37.3267, -79.2004), 'BWI': (39.1754, -76.6683), 'BOS': (42.3656, -71.0096),
        'DTW': (42.2124, -83.3534), 'EWN': (35.0730, -77.0430), 'MSY': (29.9934, -90.2580),
        'RSW': (26.5362, -81.7552), 'MSP': (44.8848, -93.2223), 'DCA': (38.8521, -77.0377),
        'BHM': (33.5629, -86.7535), 'IAH': (29.9902, -95.3368), 'HPN': (41.0670, -73.7076)
    }

    for idx, row in df.iterrows():
        code = row['Destination']
        coords = airport_coords.get(code, (0, 0))

        trip = {
            'code': code,
            'city': row['City'],
            'groundTime': parse_time_to_minutes(row['Time at Destination']),
            'timeStr': row['Time at Destination'],
            'departCLT': row['Depart CLT'],
            'arriveCLT': row['Arrive CLT'],
            'lat': coords[0],
            'lon': coords[1],
        }

        # Add real pricing if available
        if pd.notna(row.get('Real Total Flight Cost')):
            trip['flight'] = round(float(row['Real Total Flight Cost']), 2)
            trip['hasPricing'] = True
            trip['priceSource'] = 'real'
        else:
            # Fallback to estimate if no real price found
            trip['flight'] = 150  # Default estimate
            trip['hasPricing'] = False
            trip['priceSource'] = 'estimate'

        # Estimate car rental (we can update this later with real data)
        # Using the estimates from original HTML
        car_estimates = {
            'ATL': 38, 'MIA': 55, 'LGA': 75, 'JFK': 75, 'ILM': 45,
            'CHS': 42, 'RIC': 40, 'MYR': 48, 'EWR': 70, 'ROA': 40,
            'ORD': 60, 'TYS': 42, 'SAV': 40, 'CHO': 42, 'FAY': 42,
            'FLL': 52, 'ORF': 38, 'IND': 42, 'CHA': 38, 'TPA': 48,
            'PHL': 60, 'MDT': 40, 'CLE': 45, 'STL': 45, 'BNA': 45,
            'MCO': 50, 'JAX': 45, 'MEM': 42, 'TRI': 40, 'GSO': 40,
            'LYH': 38, 'BWI': 55, 'BOS': 65, 'DTW': 48, 'EWN': 40,
            'MSY': 42, 'RSW': 48, 'MSP': 55, 'DCA': 65, 'BHM': 40,
            'IAH': 50, 'HPN': 80
        }

        trip['car'] = car_estimates.get(row['Destination'], 45)

        trips.append(trip)

    # Generate JavaScript file
    print(f"Generating {OUTPUT_FILE}...")

    js_content = f"""// CLT Same-Day Trip Data
// Generated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
// Source: {INPUT_FILE}
// Real pricing from Amadeus API

const TRIPS_DATA = {json.dumps(trips, indent=2)};

// Export for use in HTML pages
if (typeof module !== 'undefined' && module.exports) {{
    module.exports = TRIPS_DATA;
}}
"""

    try:
        with open(OUTPUT_FILE, 'w') as f:
            f.write(js_content)
        print(f"[SUCCESS] Generated {OUTPUT_FILE}")
    except Exception as e:
        print(f"[ERROR] Failed to write file: {e}")
        return

    # Print summary
    print()
    print("SUMMARY:")
    print(f"  Total destinations: {len(trips)}")

    with_pricing = len([t for t in trips if t['hasPricing']])
    without_pricing = len(trips) - with_pricing

    print(f"  With real pricing: {with_pricing}")
    print(f"  With estimated pricing: {without_pricing}")

    if with_pricing > 0:
        real_prices = [t['flight'] for t in trips if t['hasPricing']]
        print()
        print(f"  Average real flight price: ${sum(real_prices)/len(real_prices):.2f}")
        print(f"  Cheapest flight: ${min(real_prices):.2f}")
        print(f"  Most expensive: ${max(real_prices):.2f}")

    print()
    print("=" * 80)
    print("Done! You can now include this file in your HTML:")
    print('  <script src="trips_data.js"></script>')
    print("=" * 80)

if __name__ == "__main__":
    generate_data_js()
