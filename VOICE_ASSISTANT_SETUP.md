# Voice Assistant Setup Guide

Your app now has **BOTH text chat and voice assistant** with Google Maps grounding!

## What's New (Latest Update)

The voice assistant has been upgraded with powerful new features:
- **Real-time Directions**: Opens Google Maps navigation in new tab
- **Live Travel Times**: Calculates duration with current traffic
- **Weather Forecasts**: Live weather data for trip planning
- **Calendar Integration**: Mock calendar events (easily extensible to real calendar)
- **Business Trip Mode**: Professional persona optimized for same-day business travelers

## Architecture

- **Text Chat**: Direct Flutter → Gemini API (REST)
- **Voice Mode**: Flutter WebView → Web App → Gemini Live API

## Setup Steps

### 1. Get Google AI API Key

Visit https://aistudio.google.com/apikey and create/copy your API key.

### 2. Configure Text Chat (Flutter)

Edit `same_day_trips_app/lib/services/gemini_service.dart:8`:
```dart
static const String apiKey = 'YOUR_API_KEY_HERE';
```

### 3. Set Up Voice Assistant (Web App)

```bash
cd same_day_trips_app/web_voice_assistant
npm install
```

Create `.env` file:
```bash
API_KEY=your_google_ai_api_key_here
```

Start the web server:
```bash
npm run dev
```

This will start at http://localhost:5173

### 4. Run Flutter App

```bash
cd same_day_trips_app
flutter pub get
flutter run -d windows
```

## How It Works

### Text Chat Mode
1. Tap "Text Chat" button on trip detail screen
2. Type questions like "Find lunch nearby"
3. Uses your GPS location automatically
4. Shows Google Maps grounded responses

### Voice Mode
1. Tap "Voice Mode" button on trip detail screen
2. Opens WebView with voice assistant
3. Speak your questions hands-free
4. Perfect for driving!

## What Gets Passed Automatically

Both modes receive:
- **Trip Context**: Destination, flights, ground time
- **GPS Location**: Auto-updated every 50-100 meters
- **Planned Stops**: Your itinerary

## URL Parameters (Voice Mode)

The Flutter app passes data via URL:
```
http://localhost:5173?lat=35.2144&lng=-80.9473&city=Atlanta&dest=ATL&groundTime=4.5&stops=2
```

The web app will use this context for all voice queries.

## Testing

### Text Chat
- Go to trip detail
- Tap "Text Chat"
- Grant location permission
- Ask: "Find coffee shops nearby"
- You should get Google Maps grounded results

### Voice Mode
1. Make sure web server is running (npm run dev)
2. Go to trip detail
3. Tap "Voice Mode"
4. Web app should load with trip context
5. Speak your questions

## Troubleshooting

**Voice Mode shows blank screen:**
- Check that `npm run dev` is running
- Verify URL in `voice_assistant_screen.dart:98` matches your server

**No Maps grounding:**
- Verify API key is set correctly
- Check browser console for errors (in Voice Mode)
- Check Flutter console for errors (in Text Chat)

**Location not working:**
- Grant location permissions when prompted
- Check that GPS is enabled on device

## Production Deployment

For production, you'll need to:
1. Build the web app: `cd web_voice_assistant && npm run build`
2. Deploy the built files to a web server
3. Update the URL in `voice_assistant_screen.dart:98` to your production URL

## Files Modified

- ✅ `lib/services/gemini_service.dart` - Text chat with Maps grounding
- ✅ `lib/screens/arrival_assistant_screen.dart` - GPS tracking for text chat
- ✅ `lib/screens/voice_assistant_screen.dart` - NEW! WebView for voice
- ✅ `lib/screens/trip_detail_screen.dart` - Added voice button
- ✅ `web_voice_assistant/` - NEW! Complete voice assistant web app
- ✅ `pubspec.yaml` - Added webview_flutter

## Switching Personas

The voice assistant supports multiple personas defined in `web_voice_assistant/lib/constants.ts`:

1. **Default Mode** (getSystemInstructions): General trip planner
2. **Business Trip Mode** (getBusinessTripInstructions): Professional, time-conscious assistant for same-day business travelers
3. **Scavenger Hunt Mode** (getScavengerHuntPrompt): Playful game master for city exploration

### Activating Business Trip Mode

To use Business Trip Mode, you need to configure the web app to use `getBusinessTripInstructions()` instead of the default. The updated web app already receives trip context from Flutter (city, destination, ground time, GPS location).

**Edit the web app configuration** to call the business trip instructions when initializing the Gemini Live session. This persona:
- Acknowledges trip details from URL parameters
- Focuses on efficiency and time management
- Prioritizes business needs (quick meals, working spaces, parking)
- Uses getTravelTime proactively
- Checks weather for planning outdoor venues
- Provides directions via Google Maps

## New Tools Available

The updated voice assistant includes these powerful tools:

### getTravelTime
Calculates real-time travel duration between locations with traffic data.
- Example: "How long to get from here to the restaurant?"
- Supports "my location" as origin

### getDirections
Opens Google Maps navigation in a new browser tab.
- Example: "Get me directions to the coffee shop"
- Builds route with optional waypoints

### getWeatherForecast
Fetches live weather data from weather.gov (US only).
- Example: "What's the weather like in Atlanta?"
- Used automatically for outdoor venue suggestions

### getTodaysCalendarEvents
Returns mock calendar events (can be extended to real Google Calendar).
- Used to suggest activities that fit between appointments
- Demonstrates context-aware planning

## Customization Tips

### For Business Travelers:
The business trip persona is optimized for:
- Finding lunch near meeting locations
- Locating coffee shops with WiFi for working
- Quick dining options near airports
- Parking recommendations
- Time-efficient routing

### Example Queries in Business Mode:
- "Find a quiet coffee shop near my meeting on Main Street"
- "I need lunch within 10 minutes of the conference center"
- "What's the weather? Should I look for covered parking?"
- "Get me directions to the airport with time to spare"

## Next Steps

- Configure the web app to use Business Trip Mode by default
- Customize the web app UI to match your branding
- Deploy web app to Firebase Hosting or Vercel
- Extend calendar integration with real Google Calendar API
- Add support for international weather APIs (weather.gov is US-only)
