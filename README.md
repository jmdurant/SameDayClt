# Same-Day Trip Planner

**Meet clients in person. Be home for dinner.**

A business productivity tool that finds viable same-day trips from your home airport, allowing you to build relationships through in-person meetings while maintaining work-life balance.

## 🎯 Purpose

This app solves the challenge of **geographic reach vs. family time** for business professionals. Instead of overnight trips, find destinations where you can:
- Fly out in the morning
- Have 3-5 hours for meetings
- Return home the same evening

Perfect for:
- Sales professionals building territory relationships
- Consultants meeting clients nationwide
- Business development teams
- Anyone needing face-to-face meetings without overnight stays

## 🏗️ Architecture

### Flutter App (Dart) - Pure Dart Implementation ✨
**No server required!** The app talks directly to Amadeus API for maximum performance:
- **Amadeus API Service**: Direct authentication and flight search
- **Trip Search Service**: Parallel API calls for blazing-fast results (5-15 seconds)
- **Flight Inspiration Search**: Auto-discovers viable destinations
- **Smart Filtering**: Matches same-day trip criteria (departure/arrival times, ground time)
- **Booking Links**: Generate URLs for Google Flights, Kayak, Turo

Cross-platform mobile/desktop app:
- **SearchScreen**: Set your origin, date, and meeting window preferences
- **ResultsScreen**: View all viable trips sorted by meeting time/cost/duration
- **TripDetailScreen**: Full itinerary with booking links

### Backend (Python)
**Flask Server**: DEPRECATED - No longer needed!
- The Flutter app now calls Gemini API directly for AI Arrival Assistant
- All endpoints (search, chat, Turo, rewards) are optional

**Standalone CLI Scripts**:
- **Flight Search**: Real-time flight availability and pricing
- **Award Availability**: Check frequent flyer program options (American Airlines)
- **Ground Transportation**: Turo car rental integration via Apify
- **Booking Links**: Generate affiliate links for flight comparison sites

✅ **The Flutter app is now 100% standalone - no server required!**

## 🚀 Getting Started

### Prerequisites

1. **Python 3.8+** with dependencies:
   ```bash
   pip install flask flask-cors pandas openpyxl selenium google-genai
   ```

2. **Flutter 3.0+** (already installed ✓)
   ```bash
   flutter doctor
   ```

3. **API Tokens**:
   - **Required for Arrival Assistant**: Google AI API key
   - **Optional**: Apify API token for Turo pricing, Amadeus API for CLI scripts

### Environment Setup

1. **Copy environment template**:
   ```bash
   cp .env.example .env
   ```

2. **Edit `.env`** with your API tokens:
   ```
   APIFY_API_TOKEN=your_token_here
   AMADEUS_API_KEY=your_key
   AMADEUS_API_SECRET=your_secret
   GOOGLE_AI_API_KEY=your_google_ai_key  # For Arrival Assistant
   ```

3. **Get Google AI API key** (for Arrival Assistant feature):
   - Visit https://aistudio.google.com/apikey
   - Create/copy your API key
   - Update `same_day_trips_app/lib/services/gemini_service.dart:8`
   - Replace `YOUR_GOOGLE_AI_API_KEY` with your actual key

4. **Update Flutter API service** (same_day_trips_app/lib/services/api_service.dart:7):
   - Replace `YOUR_APIFY_TOKEN_HERE` with your actual token
   - Or implement proper environment variable handling

### Running the App

**100% Standalone - No server needed!** 🎉

**Windows Desktop**:
```bash
cd same_day_trips_app
flutter run -d windows
```

**Android**:
```bash
flutter run -d <device_id>
```

**iOS** (macOS only):
```bash
flutter run -d <device_id>
```

**Or build a standalone executable**:
```bash
cd same_day_trips_app
flutter build windows --release
# Executable at: build\windows\x64\runner\Release\same_day_trips_app.exe
```

The AI Arrival Assistant will work with full Google Maps grounding using direct Gemini API calls - no backend required!

## 📱 Using the App

### 1. Search Configuration

- **Home Airport**: Your starting location (e.g., CLT, ATL, LAX)
- **Travel Date**: When you want to travel
- **Depart By**: Latest time you want to leave home
- **Return By**: Time you need to be back
- **Return After**: Latest time to start return journey
- **Meeting Time**: Minimum hours needed on the ground
- **Max Flight Time**: Longest acceptable flight each way
- **Destinations**: Optional filter for specific cities

### 2. Review Results

Results show all viable trips with:
- **Meeting Time** (highlighted) - Your productive hours in the city
- **Flight Schedule** - Departure and arrival times
- **Total Cost** - Round-trip flight pricing
- **Flight Details** - Stops, duration, flight numbers

Sort by:
- Ground time (maximize meeting hours)
- Cost (find budget-friendly options)
- Total trip time (minimize travel time)

### 3. Plan Your Stops

After selecting a trip, you can plan your itinerary:
- **Add Stops** - Search for POIs, offices, restaurants using Mapbox search
- **Set Duration** - Specify how long you'll spend at each location (15 min - 4 hours)
- **Route Planning** - Automatically calculates drive times between stops
- **Feasibility Check** - Ensures your stops fit within available ground time

### 4. Arrival Assistant (AI-Powered)

**No backend required!** Direct Gemini API integration with Maps grounding.

Once you arrive, activate the AI Arrival Assistant for real-time help:
- **Contextual Recommendations** - Gemini AI with Google Maps grounding
- **GPS Location Tracking** - Automatically uses your current location
- **Trip-Aware** - Knows your itinerary and planned stops
- **Real-Time Places** - Gets actual place recommendations from Google Maps
- **Quick Suggestions** - One-tap queries for common needs

How it works:
1. Tap "Start AI Arrival Assistant" on trip detail screen
2. Grant location permission when prompted
3. Ask natural language questions
4. Get responses grounded in real Google Maps data

Example queries:
- "Find lunch near my next meeting"
- "Coffee shops within 5 minutes of here"
- "Where's the best place to work for an hour?"
- "Fastest route to the airport?"

The assistant sees:
- Your current GPS location (updates every 50 meters)
- Your planned stops and their addresses
- Your available ground time
- Flight schedule context

### 5. Book Your Trip

Each trip includes:
- **Google Flights** - Compare prices across airlines
- **Kayak** - Multi-site price comparison
- **Direct Airline** - Book straight from carrier
- **Turo** - Rent a car at destination

## 🗂️ Project Structure

```
SameDayClt/
├── same_day_trips_app/          # Flutter mobile/desktop app
│   ├── lib/
│   │   ├── main.dart            # App entry point
│   │   ├── models/
│   │   │   ├── trip.dart        # Trip data model
│   │   │   ├── stop.dart        # Stop/POI model for itinerary planning
│   │   │   └── flight_offer.dart  # Flight, Destination, SearchCriteria models
│   │   ├── screens/
│   │   │   ├── search_screen.dart          # Search interface
│   │   │   ├── results_screen.dart         # Results list
│   │   │   ├── trip_detail_screen.dart     # Trip details + stops planning
│   │   │   └── arrival_assistant_screen.dart # AI chat assistant
│   │   └── services/
│   │       ├── api_service.dart         # Main API facade
│   │       ├── amadeus_service.dart     # Amadeus API client
│   │       ├── trip_search_service.dart # Trip search logic
│   │       ├── mapbox_service.dart      # Mapbox location/routing API
│   │       └── gemini_service.dart      # Gemini AI with Maps grounding (direct API)
│   ├── api/
│   │   └── server.py            # Flask API server (DEPRECATED)
│   └── pubspec.yaml             # Flutter dependencies
│
├── find_same_day_trips.py       # Main trip search script (CLI)
├── update_all_pricing.py        # Pricing update utilities (CLI)
├── booking_links.py             # Generate booking URLs
├── affiliate_links.py           # Affiliate link generation
├── clt_price_fetcher.py         # Flight price scraping
├── fetch_award_pricing.py       # Award availability checker
└── .env.example                 # Environment template
```

## 🔧 Configuration

### Customizing Search Defaults

Edit `same_day_trips_app/lib/screens/search_screen.dart`:

```dart
String _origin = 'CLT';           // Your home airport
int _departBy = 9;                // Depart by 9 AM
int _returnAfter = 15;            // Start return after 3 PM
int _returnBy = 19;               // Back by 7 PM
double _minGroundTime = 3.0;      // 3 hours minimum
int _maxDuration = 204;           // 3.4 hours max flight
```

### Adding Destination Options

Update the destination filter in search_screen.dart:188:

```dart
final List<String> _destinationOptions = [
  'ATL', 'BOS', 'DCA', 'DEN', 'DFW', 'EWR', 'IAH', 'JFK',
  'LAX', 'LGA', 'MIA', 'ORD', 'PHL', 'PHX', 'SFO', 'SEA',
  // Add your frequently visited airports
];
```

## 🧪 Testing

```bash
cd same_day_trips_app
flutter test
```

## 📊 Python Scripts (Standalone Usage)

### Find Same-Day Trips
```bash
python find_same_day_trips.py \
  --date 2025-11-15 \
  --origin CLT \
  --depart-by 9 \
  --return-by 19 \
  --output results.xlsx
```

### Update Pricing Data
```bash
python update_all_pricing.py \
  --apify-token YOUR_TOKEN \
  --date 2025-11-15
```

## 🛠️ Development Status

### ✅ Completed
- [x] Flutter environment setup
- [x] Python backend scripts (CLI standalone)
- [x] ~~Flask API server~~ **REPLACED with direct Amadeus API!**
- [x] **Pure Dart implementation - no server required!**
- [x] **Parallel API calls (5-15 second searches)**
- [x] **Auto-discovery of destinations via Flight Inspiration Search**
- [x] Search screen with business focus
- [x] Results display with sorting
- [x] Trip detail view
- [x] **Multi-stop itinerary planning with Mapbox search**
- [x] **AI Arrival Assistant with Gemini + Google Maps grounding**
- [x] **Route planning with drive time calculations**
- [x] Booking link generation
- [x] Cross-platform support (Windows, Android, iOS)
- [x] Basic testing

### 🚧 Future Enhancements
- [ ] Environment variable handling in Flutter (use flutter_dotenv)
- [x] **GPS location tracking** - Completed! Auto-updates every 50 meters
- [ ] Production Amadeus API credentials (TEST API has limited data)
- [ ] Route timeline visualization on trip detail screen
- [ ] Gemini Live voice assistant (hands-free while driving)
- [ ] Save favorite routes/searches
- [ ] Multi-date search (show all viable days this week)
- [ ] Calendar integration
- [ ] Offline mode with cached searches
- [ ] Push notifications for price drops
- [ ] Travel time to/from airport calculation
- [ ] Export itinerary to PDF/email

## 💡 Tips for Effective Day Trips

1. **TSA PreCheck/Clear** - Save 20-30 minutes per airport
2. **Pack Light** - Personal item only (no checked bags)
3. **Schedule Near Airport** - Maximize ground time
4. **Download Airline Apps** - Mobile boarding passes
5. **Morning Departures** - More reliable than afternoon
6. **Nonstop Preferred** - Minimize delays and maximize time
7. **Plan Meetings Around Lunch** - Natural gathering time

## 📝 Notes

### Performance
- **Search times**: 5-15 seconds for comprehensive results (with parallel API calls!)
- **Auto-discovery**: Automatically finds all viable destinations from any airport
- **No server required**: Pure Dart implementation, runs entirely on device

### Data Sources
- **Pricing data**: Real-time from Amadeus API
- **Flight discovery**: Flight Inspiration Search API
- **Award availability**: Requires browser automation (AA only) - CLI only
- **Turo pricing**: Requires Apify token - CLI only

### Architecture Notes
- **100% standalone**: No server required - everything runs client-side in Flutter!
- **Direct Gemini API**: Uses REST API with Google Maps grounding tool
- **Trip search**: Pure Dart implementation with direct Amadeus API calls
- **Python scripts**: Still available for CLI standalone use
- **Parallel execution**: Up to 10 concurrent API calls for maximum performance
- **Maps grounding**: Direct REST API calls to Gemini API (gemini-2.0-flash-exp model)
- **Location tracking**: Geolocator 14.0.2 with 50m update threshold
- **No affiliate monetization**: Not implemented yet

## 🤝 Contributing

This is a personal productivity tool, but suggestions welcome:
1. Open an issue describing the enhancement
2. Fork the repository
3. Create a feature branch
4. Submit a pull request

## 📄 License

Personal use project - not licensed for commercial distribution.

## 🙏 Acknowledgments

Built with:
- Flutter for cross-platform UI
- Flask for API layer
- Python for flight search automation
- Apify for web scraping capabilities

---

**Remember**: The best business relationships are built in person. This tool helps you do that without sacrificing family time.
