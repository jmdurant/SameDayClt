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

# Add root directory to path to import existing scripts
# server.py is in same_day_trips_app/api/, so go up 2 levels to reach root
root_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, root_dir)

# Import booking link generator
# from booking_links import add_booking_links_to_trip  # COMMENTED OUT TEMPORARILY

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
    import sys
    sys.stdout.flush()
    sys.stderr.flush()
    print("=" * 70, flush=True)
    print("RECEIVED /api/search REQUEST", flush=True)
    print("=" * 70, flush=True)
    try:
        data = request.json

        # Build command to run find_same_day_trips.py
        cmd = [
            'python',
            '-u',  # Unbuffered output so we can see progress
            os.path.join(root_dir, 'find_same_day_trips.py'),
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
            cwd=root_dir
        )

        if result.returncode != 0:
            return jsonify({
                'error': 'Script execution failed',
                'details': result.stderr
            }), 500

        # Read the results
        full_path = os.path.join(root_dir, output_file)

        if not os.path.exists(full_path):
            # No results file means no trips found - return empty array
            return jsonify({
                'success': True,
                'count': 0,
                'trips': [],
                'message': 'No viable trips found for the selected criteria'
            })

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
            # trip_dict = add_booking_links_to_trip(trip_dict)  # COMMENTED OUT TEMPORARILY

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


@app.route('/api/chat', methods=['POST'])
def chat():
    """
    AI chat endpoint with Google Maps grounding.

    Request body:
    {
        "query": "Find lunch nearby",
        "latitude": 35.2144,
        "longitude": -80.9473,
        "tripContext": {...},
        "stopsContext": [...]
    }
    """
    try:
        from google import genai
        from google.genai import types

        data = request.json

        # Get Google AI API key from environment
        api_key = os.environ.get('GOOGLE_AI_API_KEY', 'YOUR_GOOGLE_AI_API_KEY')

        if api_key == 'YOUR_GOOGLE_AI_API_KEY':
            return jsonify({
                'error': 'Google AI API key not configured. Set GOOGLE_AI_API_KEY environment variable.'
            }), 500

        # Initialize Gemini client
        client = genai.Client(api_key=api_key)

        # Build context prompt
        query = data.get('query', '')
        trip_context = data.get('tripContext')
        stops_context = data.get('stopsContext', [])

        context_prompt = query

        if trip_context:
            location_info = ''
            if data.get('latitude') and data.get('longitude'):
                location_info = f"- Current Location: Lat {data['latitude']}, Long {data['longitude']}\n"

            trip_info = f'''
You are helping a business traveler on a same-day trip.

Trip Details:
- Destination: {trip_context.get('city')} ({trip_context.get('destination')})
- Date: {trip_context.get('date')}
{location_info}- Outbound: {trip_context.get('departOrigin')} → {trip_context.get('arriveDestination')} ({trip_context.get('outboundFlight')})
- Return: {trip_context.get('departDestination')} → {trip_context.get('arriveOrigin')} ({trip_context.get('returnFlight')})
- Available ground time: {trip_context.get('groundTime')}
'''

            if stops_context:
                stops_info = '\n'.join([f"{i+1}. {stop.get('name')} ({stop.get('address')}) - {stop.get('duration')}"
                                       for i, stop in enumerate(stops_context)])
                context_prompt = f'''{trip_info}

Planned stops:
{stops_info}

User question: {query}

Provide helpful, location-specific recommendations based on their itinerary and current context.'''
            else:
                context_prompt = f'''{trip_info}

User question: {query}

Provide helpful, location-specific recommendations for their trip.'''

        # Configure with Google Maps grounding
        config = types.GenerateContentConfig(
            tools=[types.Tool(google_maps=types.GoogleMaps())],
        )

        # Add location if provided
        if data.get('latitude') and data.get('longitude'):
            config.tool_config = types.ToolConfig(
                retrieval_config=types.RetrievalConfig(
                    lat_lng=types.LatLng(
                        latitude=data['latitude'],
                        longitude=data['longitude']
                    )
                )
            )

        # Call Gemini
        response = client.models.generate_content(
            model='gemini-2.0-flash-exp',
            contents=context_prompt,
            config=config,
        )

        # Extract response
        response_text = response.text if hasattr(response, 'text') else 'No response'

        # Extract grounding metadata
        places = []
        has_map_data = False

        if hasattr(response, 'candidates') and response.candidates:
            candidate = response.candidates[0]
            if hasattr(candidate, 'grounding_metadata') and candidate.grounding_metadata:
                has_map_data = True
                grounding = candidate.grounding_metadata

                # Extract places from grounding chunks
                if hasattr(grounding, 'grounding_chunks'):
                    for chunk in grounding.grounding_chunks:
                        if hasattr(chunk, 'maps') and chunk.maps:
                            places.append({
                                'name': chunk.maps.title if hasattr(chunk.maps, 'title') else 'Unknown',
                                'uri': chunk.maps.uri if hasattr(chunk.maps, 'uri') else ''
                            })

        return jsonify({
            'success': True,
            'text': response_text,
            'places': places,
            'hasMapData': has_map_data
        })

    except ImportError:
        return jsonify({
            'error': 'google-genai package not installed. Run: pip install google-genai'
        }), 500
    except Exception as e:
        print(f'Chat error: {e}')
        return jsonify({
            'error': str(e),
            'text': f'Sorry, I encountered an error: {str(e)}',
            'places': [],
            'hasMapData': False
        }), 500


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
    print("  POST /api/chat - AI chat with Maps grounding")
    print("  POST /api/check-turo - Check Turo pricing")
    print("  POST /api/check-rewards - Check AA rewards")
    print("  GET  /api/health - Health check")
    print("=" * 70)

    app.run(debug=False, host='0.0.0.0', port=5000)
