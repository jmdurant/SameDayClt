"""
Flask API Server for Same-Day Trips App

This API wraps the existing Python scripts to provide endpoints for the Flutter app.
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
import sys
import os
import subprocess
import json
import pandas as pd

# Add parent directory to path to import existing scripts
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Import booking link generator
from booking_links import add_booking_links_to_trip

app = Flask(__name__)
CORS(app)  # Enable CORS for Flutter web/mobile

# Airport coordinates for map (sample - you can expand this)
AIRPORT_COORDS = {
    'CLT': {'lat': 35.2144, 'lng': -80.9473},
    'ATL': {'lat': 33.6407, 'lng': -84.4277},
    'MIA': {'lat': 25.7959, 'lng': -80.2870},
    'BOS': {'lat': 42.3656, 'lng': -71.0096},
    'NYC': {'lat': 40.6413, 'lng': -73.7781},
    'JFK': {'lat': 40.6413, 'lng': -73.7781},
    'LAX': {'lat': 33.9416, 'lng': -118.4085},
    'ORD': {'lat': 41.9742, 'lng': -87.9073},
    'DFW': {'lat': 32.8998, 'lng': -97.0403},
    'DEN': {'lat': 39.8561, 'lng': -104.6737},
    'PHX': {'lat': 33.4352, 'lng': -112.0101},
}


@app.route('/api/search', methods=['POST'])
def search_trips():
    """
    Search for same-day trips based on user criteria.

    Request body:
    {
        "origin": "CLT",
        "date": "2025-11-15",
        "departBy": 9,
        "returnAfter": 15,
        "returnBy": 19,
        "minGroundTime": 3.0,
        "maxDuration": 204,
        "destinations": ["ATL", "MIA"] or null for all
    }
    """
    try:
        data = request.json

        # Build command to run find_same_day_trips.py
        cmd = [
            'python',
            '../find_same_day_trips.py',
            '--date', data['date'],
            '--origin', data.get('origin', 'CLT'),
            '--depart-by', str(data.get('departBy', 9)),
            '--return-after', str(data.get('returnAfter', 15)),
            '--return-by', str(data.get('returnBy', 19)),
            '--min-ground-time', str(data.get('minGroundTime', 3.0)),
            '--max-duration', str(data.get('maxDuration', 204)),
        ]

        # Add destination filter if specified
        if data.get('destinations') and len(data['destinations']) > 0:
            cmd.extend(['--destinations'] + data['destinations'])

        # Set output file
        output_file = f"temp_{data['origin']}_{data['date']}.xlsx"
        cmd.extend(['--output', output_file])

        print(f"Running command: {' '.join(cmd)}")

        # Run the script
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300,  # 5 minute timeout
            cwd=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        )

        if result.returncode != 0:
            return jsonify({
                'error': 'Script execution failed',
                'details': result.stderr
            }), 500

        # Read the results
        full_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            output_file
        )

        if not os.path.exists(full_path):
            return jsonify({
                'error': 'No results file generated',
                'output': result.stdout
            }), 404

        # Load results from Excel
        df = pd.read_excel(full_path)

        # Add coordinates and booking links
        trips = []
        for _, row in df.iterrows():
            trip_dict = row.to_dict()

            # Add destination coordinates if available
            dest = trip_dict.get('Destination', '')
            if dest in AIRPORT_COORDS:
                trip_dict['lat'] = AIRPORT_COORDS[dest]['lat']
                trip_dict['lng'] = AIRPORT_COORDS[dest]['lng']

            # Add origin coordinates
            origin = trip_dict.get('Origin', data.get('origin', 'CLT'))
            if origin in AIRPORT_COORDS:
                trip_dict['origin_lat'] = AIRPORT_COORDS[origin]['lat']
                trip_dict['origin_lng'] = AIRPORT_COORDS[origin]['lng']

            # Add booking links
            trip_dict = add_booking_links_to_trip(trip_dict)

            trips.append(trip_dict)

        # Clean up temp file
        try:
            os.remove(full_path)
        except:
            pass

        return jsonify({
            'success': True,
            'count': len(trips),
            'trips': trips
        })

    except subprocess.TimeoutExpired:
        return jsonify({'error': 'Search timed out'}), 504
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/check-turo', methods=['POST'])
def check_turo():
    """
    Check Turo pricing for a specific trip.

    Request body:
    {
        "city": "Atlanta",
        "pickupDatetime": "2025-11-15T10:00",
        "returnDatetime": "2025-11-15T18:00",
        "apifyToken": "apify_api_..."
    }
    """
    try:
        data = request.json

        # Import the fetch_turo_pricing function from update_all_pricing.py
        sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        from update_all_pricing import fetch_turo_pricing

        result = fetch_turo_pricing(
            data['apifyToken'],
            data['city'],
            data['pickupDatetime'],
            data['returnDatetime']
        )

        if result:
            if isinstance(result, dict):
                return jsonify({
                    'success': True,
                    'price': result.get('price'),
                    'url': result.get('url'),
                    'vehicle': result.get('vehicle')
                })
            else:
                # Backwards compatibility
                return jsonify({
                    'success': True,
                    'price': result
                })
        else:
            return jsonify({
                'success': False,
                'message': 'No Turo pricing found'
            })

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/check-rewards', methods=['POST'])
def check_rewards():
    """
    Check AA award availability for a specific route.

    Request body:
    {
        "origin": "CLT",
        "destination": "ATL",
        "date": "2025-11-15",
        "departTime": "06:00"
    }
    """
    try:
        data = request.json

        # Import the fetch_award_pricing function
        sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        from update_all_pricing import fetch_award_pricing

        # Note: This would require a browser driver instance
        # For now, return a placeholder response
        # You'll need to implement proper browser handling

        return jsonify({
            'success': False,
            'message': 'Award checking requires browser automation - not yet implemented in API'
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/health', methods=['GET'])
def health():
    """Health check endpoint."""
    return jsonify({'status': 'ok'})


if __name__ == '__main__':
    print("=" * 70)
    print("SAME-DAY TRIPS API SERVER")
    print("=" * 70)
    print("Server starting on http://localhost:5000")
    print("Endpoints:")
    print("  POST /api/search - Search for same-day trips")
    print("  POST /api/check-turo - Check Turo pricing")
    print("  POST /api/check-rewards - Check AA rewards")
    print("  GET  /api/health - Health check")
    print("=" * 70)

    app.run(debug=True, host='0.0.0.0', port=5000)
