# Voice Assistant Setup

This is the Gemini Live voice assistant for hands-free use while driving.

## Quick Start

1. **Install dependencies**:
   ```bash
   cd same_day_trips_app/web_voice_assistant
   npm install
   ```

2. **Create `.env` file**:
   ```bash
   API_KEY=your_google_ai_api_key_here
   ```

3. **Run the dev server**:
   ```bash
   npm run dev
   ```
   Server will start at http://localhost:5173

## Integration with Flutter App

The Flutter app will open this in a WebView and pass:
- Trip context (destination, flights, ground time)
- GPS location (auto-updated)
- Planned stops

## URL Parameters

When Flutter opens the WebView, it will pass data via URL:
- `?lat=35.2144&lng=-80.9473` - Current GPS location
- `&city=Atlanta&dest=ATL` - Trip destination
- `&groundTime=4.5` - Available hours

The voice assistant will automatically use this context for all queries.
