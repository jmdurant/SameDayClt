# Same-Day Trips Flutter App

A cross-platform mobile/web/desktop app for finding viable same-day round trips from any airport.

## Features

- **Flexible Search**: Choose origin airport, date, departure/return time windows
- **Interactive Map**: Visualize routes with color-coded ground time
- **Sortable Table**: View and sort results by price, ground time, destination
- **On-Demand Pricing**: Click to check Turo car rental prices
- **Award Availability**: Click to check AA reward availability (coming soon)
- **Export Results**: Download results as Excel spreadsheet

## Architecture

```
Flutter App (Frontend)
    ↓ HTTP/REST
Flask API (Backend)
    ↓ subprocess
Python Scripts (find_same_day_trips.py, etc.)
    ↓ HTTP
Amadeus API / Turo API
```

## Setup Instructions

### 1. Install Flutter

Download and install Flutter from https://flutter.dev/docs/get-started/install

Verify installation:
```bash
flutter doctor
```

### 2. Install Python Dependencies for API

```bash
cd api
pip install -r requirements.txt
```

### 3. Get Flutter Dependencies

```bash
cd ..
flutter pub get
```

### 4. Start the Backend API

```bash
cd api
python server.py
```

The API will start on `http://localhost:5000`

### 5. Run the Flutter App

In a new terminal:

```bash
# For mobile (iOS/Android)
flutter run

# For web
flutter run -d chrome

# For desktop
flutter run -d windows  # or macos, linux
```

## Project Structure

```
same_day_trips_app/
├── lib/
│   ├── main.dart                 # App entry point
│   ├── models/
│   │   └── trip.dart             # Trip data model
│   ├── services/
│   │   └── api_service.dart      # API client
│   ├── screens/
│   │   ├── search_screen.dart    # Search form
│   │   └── results_screen.dart   # Results (table + map tabs)
│   └── widgets/
│       ├── trip_table.dart       # Sortable table widget
│       └── trip_map.dart         # Interactive map widget
├── api/
│   ├── server.py                 # Flask backend
│   └── requirements.txt          # Python dependencies
└── pubspec.yaml                  # Flutter dependencies
```

## API Endpoints

### POST /api/search
Search for same-day trips

Request:
```json
{
  "origin": "CLT",
  "date": "2025-11-15",
  "departBy": 9,
  "returnAfter": 15,
  "returnBy": 19,
  "minGroundTime": 3.0,
  "maxDuration": 204,
  "destinations": ["ATL", "MIA"]  // optional
}
```

Response:
```json
{
  "success": true,
  "count": 10,
  "trips": [...]
}
```

### POST /api/check-turo
Check Turo pricing for a trip

Request:
```json
{
  "city": "Atlanta",
  "pickupDatetime": "2025-11-15T10:00",
  "returnDatetime": "2025-11-15T18:00",
  "apifyToken": "apify_api_..."
}
```

### POST /api/check-rewards
Check AA award availability (coming soon)

## Configuration

### Add Your API Tokens

Edit `lib/services/api_service.dart` and add your tokens:

```dart
static const String APIFY_TOKEN = 'apify_api_YOUR_TOKEN_HERE';
```

### Add More Airport Coordinates

Edit `api/server.py` and expand the `AIRPORT_COORDS` dictionary:

```python
AIRPORT_COORDS = {
    'CLT': {'lat': 35.2144, 'lng': -80.9473},
    'ATL': {'lat': 33.6407, 'lng': -84.4277},
    # Add more airports...
}
```

## Usage

1. **Select Search Parameters**
   - Choose origin airport (default: CLT)
   - Pick travel date
   - Adjust time sliders for departure/return windows
   - Set minimum ground time
   - Optionally filter to specific destinations

2. **View Results**
   - **Table Tab**: Sort by any column, click headers
   - **Map Tab**: See routes on map, color-coded by ground time

3. **Check Additional Pricing**
   - Click "Check Turo" button on any row to get car rental prices
   - Click "Check Rewards" to see award availability (coming soon)

4. **Export**
   - Click "Export to Excel" to download results

## Customization

### Change Default Values

Edit `lib/screens/search_screen.dart`:

```dart
int _departBy = 9;          // Latest departure hour
int _returnAfter = 15;      // Earliest return hour
int _returnBy = 19;         // Latest return hour
double _minGroundTime = 3.0; // Minimum ground time
int _maxDuration = 204;     // Max flight duration (minutes)
```

### Change Color Scheme

Edit `lib/main.dart`:

```dart
primarySwatch: Colors.blue,  // Change app color
```

## Troubleshooting

### API Connection Error
- Ensure Flask server is running on port 5000
- Check firewall settings
- Verify API endpoint in `lib/services/api_service.dart`

### No Results Found
- Check that Amadeus API credentials are valid
- Try expanding time windows
- Increase max flight duration
- Check API logs in Flask console

### Map Not Loading
- Ensure internet connection (uses OpenStreetMap)
- Check airport coordinates in `api/server.py`

## Future Enhancements

- [ ] Implement AA reward checking in API
- [ ] Add price history tracking
- [ ] Push notifications for price drops
- [ ] Multi-city trip planning
- [ ] Offline mode with cached results
- [ ] User accounts and saved searches
- [ ] Calendar view of best dates

## License

Created for CLT Same-Day Trip Planner Project
