"""
Affiliate Link Generators - Monetize your Same-Day Trips App

This module adds affiliate/referral tracking to booking links to earn commissions.
"""

from urllib.parse import urlencode, urlparse, parse_qs, urljoin
from booking_links import (
    generate_google_flights_url,
    generate_kayak_url,
    generate_turo_search_url
)


# ============================================================================
# YOUR AFFILIATE IDs (Replace with your actual IDs after signing up)
# ============================================================================

SKYSCANNER_AFFILIATE_ID = "YOUR_SKYSCANNER_ID"  # Get from partners.skyscanner.net
KAYAK_AFFILIATE_ID = "YOUR_KAYAK_AID"  # Get from booking.com affiliate program
TURO_REFERRAL_CODE = "YOUR_TURO_CODE"  # Get from turo.com/referral
BOOKING_AFFILIATE_ID = "YOUR_BOOKING_ID"  # For future hotel feature


# ============================================================================
# FLIGHT AFFILIATE LINKS
# ============================================================================

def generate_skyscanner_affiliate_url(origin, destination, departure_date, return_date=None):
    """
    Generate Skyscanner affiliate link (EARNS COMMISSION).

    Skyscanner pays per click AND per booking.
    Typical earnings: $0.50-$2 per click + 3-5% of booking.
    """
    # Skyscanner URL format
    if return_date:
        # Round trip
        url = f"https://www.skyscanner.com/transport/flights/{origin}/{destination}/{departure_date}/{return_date}/"
    else:
        # One way
        url = f"https://www.skyscanner.com/transport/flights/{origin}/{destination}/{departure_date}/"

    # Add affiliate parameter
    params = {
        'adultsv2': '1',
        'cabinclass': 'economy',
        'children': '0',
        'inboundaltsenabled': 'false',
        'outboundaltsenabled': 'false',
        'ref': 'home',
        'rtn': '1' if return_date else '0',
        # IMPORTANT: Add your affiliate ID
        'associate_id': SKYSCANNER_AFFILIATE_ID,
    }

    query_string = urlencode(params)
    return f"{url}?{query_string}"


def generate_kayak_affiliate_url(origin, destination, departure_date, return_date=None):
    """
    Generate Kayak affiliate link (EARNS COMMISSION).

    Kayak is part of Booking.com affiliate network.
    Typical earnings: CPA (cost per acquisition) varies by market.
    """
    if return_date:
        url = f"https://www.kayak.com/flights/{origin}-{destination}/{departure_date}/{return_date}"
    else:
        url = f"https://www.kayak.com/flights/{origin}-{destination}/{departure_date}"

    # Add affiliate parameters
    params = {
        'sort': 'bestflight_a',
        'aid': KAYAK_AFFILIATE_ID,  # Your affiliate ID
        'sub_aid': 'same_day_trips',  # Sub-tracking for analytics
    }

    query_string = urlencode(params)
    return f"{url}?{query_string}"


def generate_momondo_affiliate_url(origin, destination, departure_date, return_date=None):
    """
    Generate Momondo affiliate link (EARNS COMMISSION).

    Similar commission structure to Kayak.
    """
    # Momondo uses different URL structure
    params = {
        'Search': 'true',
        'DestinationAirportCode': destination,
        'OriginAirportCode': origin,
        'DepartureDate': departure_date,
        'ReturnDate': return_date or '',
        'TripType': 'RoundTrip' if return_date else 'OneWay',
        # Add affiliate tracking
        'aid': KAYAK_AFFILIATE_ID,  # Uses same system as Kayak
    }

    query_string = urlencode(params)
    return f"https://www.momondo.com/flight-search?{query_string}"


# ============================================================================
# CAR RENTAL AFFILIATE LINKS
# ============================================================================

def generate_turo_affiliate_url(city, pickup_date, return_date, pickup_time="10:00", return_time="18:00"):
    """
    Generate Turo referral link (EARNS $25-$50 PER SIGNUP).

    When a new user signs up via your link, you both get credits.
    """
    # Start with regular Turo search URL
    base_url = generate_turo_search_url(city, pickup_date, return_date, pickup_time, return_time)

    # Add referral code
    params = {
        'ref': TURO_REFERRAL_CODE,  # Your Turo referral code
    }

    # Append to existing URL
    parsed = urlparse(base_url)
    existing_params = parse_qs(parsed.query)
    existing_params.update(params)

    query_string = urlencode(existing_params, doseq=True)
    return f"{parsed.scheme}://{parsed.netloc}{parsed.path}?{query_string}"


def add_turo_referral_to_url(turo_url):
    """
    Add referral code to existing Turo URL (from Apify scraper).

    If Apify returns a direct vehicle link, add your referral code.
    """
    if not turo_url or TURO_REFERRAL_CODE == "YOUR_TURO_CODE":
        return turo_url

    # Add referral parameter
    separator = '&' if '?' in turo_url else '?'
    return f"{turo_url}{separator}ref={TURO_REFERRAL_CODE}"


# ============================================================================
# HOTEL AFFILIATE LINKS (Future Feature)
# ============================================================================

def generate_booking_com_affiliate_url(city, checkin_date, checkout_date):
    """
    Generate Booking.com affiliate link (EARNS 25-40% COMMISSION).

    This is one of the HIGHEST earning affiliate programs.
    Average commission: $20-$50 per booking.
    """
    params = {
        'ss': city,
        'checkin': checkin_date,
        'checkout': checkout_date,
        'group_adults': '1',
        'group_children': '0',
        'no_rooms': '1',
        # IMPORTANT: Your affiliate ID
        'aid': BOOKING_AFFILIATE_ID,
        'label': 'same-day-trips',  # Sub-tracking
    }

    query_string = urlencode(params)
    return f"https://www.booking.com/searchresults.html?{query_string}"


# ============================================================================
# SMART LINK SELECTOR (Choose best affiliate for user)
# ============================================================================

def get_best_flight_affiliate_link(origin, destination, departure_date, return_date=None, user_preference=None):
    """
    Choose the best affiliate link based on user preference or highest commission.

    Returns dict with multiple options so user can choose.
    """
    links = {
        'skyscanner': {
            'url': generate_skyscanner_affiliate_url(origin, destination, departure_date, return_date),
            'name': 'Skyscanner',
            'earning_potential': 'medium',  # $0.50-2 per click
            'user_friendly': 'high',
        },
        'kayak': {
            'url': generate_kayak_affiliate_url(origin, destination, departure_date, return_date),
            'name': 'Kayak',
            'earning_potential': 'medium',  # CPA varies
            'user_friendly': 'high',
        },
        'momondo': {
            'url': generate_momondo_affiliate_url(origin, destination, departure_date, return_date),
            'name': 'Momondo',
            'earning_potential': 'medium',
            'user_friendly': 'medium',
        },
    }

    if user_preference and user_preference in links:
        return links[user_preference]

    # Default to Skyscanner (good balance of commission and UX)
    return links['skyscanner']


# ============================================================================
# AFFILIATE TRACKING & ANALYTICS
# ============================================================================

def track_affiliate_click(trip_id, affiliate_name, user_id=None):
    """
    Track when users click affiliate links (for your analytics).

    This helps you:
    - See which affiliates convert best
    - Calculate earnings
    - Optimize link placement
    """
    # Log to your database or analytics service
    print(f"[AFFILIATE CLICK] Trip: {trip_id}, Affiliate: {affiliate_name}, User: {user_id}")

    # You can integrate with:
    # - Google Analytics
    # - Mixpanel
    # - Your own database
    # - Affiliate network's tracking API


# ============================================================================
# EXAMPLE USAGE
# ============================================================================

if __name__ == '__main__':
    print("=" * 70)
    print("AFFILIATE LINK EXAMPLES")
    print("=" * 70)
    print()

    # Flight examples
    print("1. Skyscanner Affiliate Link (EARNS COMMISSION):")
    print(generate_skyscanner_affiliate_url('CLT', 'ATL', '2025-10-30', '2025-10-30'))
    print()

    print("2. Kayak Affiliate Link (EARNS COMMISSION):")
    print(generate_kayak_affiliate_url('CLT', 'ATL', '2025-10-30', '2025-10-30'))
    print()

    print("3. Turo Referral Link (EARNS $25-50 PER SIGNUP):")
    print(generate_turo_affiliate_url('Atlanta', '2025-10-30', '2025-10-30'))
    print()

    print("4. Booking.com Hotel Link (EARNS 25-40% COMMISSION):")
    print(generate_booking_com_affiliate_url('Atlanta, GA', '2025-10-30', '2025-10-31'))
    print()

    print("=" * 70)
    print("ESTIMATED EARNINGS PER TRIP BOOKING:")
    print("  - Flight booking: $2-10 (via Skyscanner/Kayak)")
    print("  - Turo signup: $25-50 (one-time per new user)")
    print("  - Hotel booking: $20-50 (if you add hotels)")
    print("  - TOTAL per complete trip: $47-110")
    print("=" * 70)
