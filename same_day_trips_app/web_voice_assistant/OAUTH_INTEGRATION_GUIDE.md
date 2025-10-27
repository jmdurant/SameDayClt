# OAuth Integration Guide for Gemini Live Function Calling

## Overview

To access personal data (Google Calendar, Gmail, Drive, etc.) from your function calling setup, you need to implement OAuth 2.0 authentication with Google APIs.

## Current Status

Your `getTodaysCalendarEvents` function is currently mocked (see `lib/tools/tool-registry.ts` line 478). It returns hardcoded calendar events instead of real data.

## OAuth 2.0 Flow for Google APIs

Here's how to add OAuth support to your web voice assistant:

### 1. Set Up Google Cloud Credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create/select your project
3. Enable the APIs you need:
   - Google Calendar API
   - Gmail API (optional)
   - Drive API (optional)
4. Create OAuth 2.0 credentials:
   - Navigate to "APIs & Services" > "Credentials"
   - Click "Create Credentials" > "OAuth client ID"
   - Choose "Web application"
   - Add authorized JavaScript origins: `http://localhost:5173` (dev) and your production domain
   - Add authorized redirect URIs: `http://localhost:5173/auth/callback`
   - Download the credentials (you'll get a Client ID and Client Secret)

### 2. Install Required Packages

```bash
cd same_day_trips_app/web_voice_assistant
npm install @google-cloud/local-auth googleapis
```

### 3. Implement OAuth in Your App

Create a new file `lib/oauth-manager.ts`:

```typescript
import { google } from 'googleapis';

// Your OAuth client ID from Google Cloud Console
const CLIENT_ID = 'YOUR_CLIENT_ID.apps.googleusercontent.com';
const REDIRECT_URI = 'http://localhost:5173/auth/callback';

export class OAuthManager {
  private auth: any = null;

  constructor() {
    this.auth = null;
  }

  async authenticate(): Promise<any> {
    // Check if we already have a token stored
    const token = localStorage.getItem('google_token');
    
    if (token) {
      this.auth = new google.auth.OAuth2({
        clientId: CLIENT_ID,
        redirectUri: REDIRECT_URI,
      });
      
      this.auth.setCredentials(JSON.parse(token));
      return this.auth;
    }

    // Start OAuth flow
    this.startOAuthFlow();
  }

  startOAuthFlow() {
    const authUrl = `https://accounts.google.com/o/oauth2/v2/auth?` +
      `client_id=${CLIENT_ID}&` +
      `redirect_uri=${encodeURIComponent(REDIRECT_URI)}&` +
      `response_type=code&` +
      `scope=${encodeURIComponent('https://www.googleapis.com/auth/calendar.readonly https://www.googleapis.com/auth/gmail.readonly')}&` +
      `access_type=offline&` +
      `prompt=consent`;

    // Redirect to Google OAuth
    window.location.href = authUrl;
  }

  async handleCallback(code: string): Promise<void> {
    const oauth2Client = new google.auth.OAuth2({
      clientId: CLIENT_ID,
      redirectUri: REDIRECT_URI,
    });

    const { tokens } = await oauth2Client.getToken(code);
    oauth2Client.setCredentials(tokens);

    // Store token for future use
    localStorage.setItem('google_token', JSON.stringify(tokens));
    
    this.auth = oauth2Client;
  }

  isAuthenticated(): boolean {
    return this.auth !== null;
  }

  async logout(): Promise<void> {
    localStorage.removeItem('google_token');
    this.auth = null;
  }
}

export const oauthManager = new OAuthManager();
```

### 4. Add OAuth Callback Route

Create `auth-callback.tsx` in your components directory:

```typescript
import { useEffect } from 'react';
import { oauthManager } from '../lib/oauth-manager';

export function AuthCallback() {
  useEffect(() => {
    const urlParams = new URLSearchParams(window.location.search);
    const code = urlParams.get('code');
    const error = urlParams.get('error');

    if (error) {
      console.error('OAuth error:', error);
      window.location.href = '/';
      return;
    }

    if (code) {
      oauthManager.handleCallback(code).then(() => {
        // Redirect back to main app
        window.location.href = '/';
      });
    }
  }, []);

  return <div>Authenticating...</div>;
}
```

### 5. Update Your App Router

In `App.tsx`, add the callback route:

```typescript
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { AuthCallback } from './components/auth-callback';

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/auth/callback" element={<AuthCallback />} />
        <Route path="/" element={<AppComponent />} />
      </Routes>
    </BrowserRouter>
  );
}
```

### 6. Update Tool Registry to Use Real Calendar Data

Update `getTodaysCalendarEvents` in `lib/tools/tool-registry.ts`:

```typescript
import { google } from 'googleapis';
import { oauthManager } from '../oauth-manager';

const getTodaysCalendarEvents: ToolImplementation = async (args, context) => {
  try {
    // Check if user is authenticated
    if (!oauthManager.isAuthenticated()) {
      return 'You need to authenticate with Google to access your calendar. Please click "Connect Calendar" first.';
    }

    const auth = oauthManager.getAuth();
    const calendar = google.calendar({ version: 'v3', auth });

    // Get today's events
    const now = new Date();
    const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const tomorrow = new Date(midnight);
    tomorrow.setDate(tomorrow.getDate() + 1);

    const response = await calendar.events.list({
      calendarId: 'primary',
      timeMin: midnight.toISOString(),
      timeMax: tomorrow.toISOString(),
      maxResults: 10,
      singleEvents: true,
      orderBy: 'startTime',
    });

    const events = response.data.items || [];

    if (events.length === 0) {
      return 'You have no events scheduled for today.';
    }

    const formattedEvents = events.map(event => ({
      summary: event.summary,
      start: event.start?.dateTime || event.start?.date,
      end: event.end?.dateTime || event.end?.date,
      location: event.location,
      description: event.description,
    }));

    return JSON.stringify(formattedEvents);
  } catch (error) {
    console.error('Error fetching calendar events:', error);
    return 'Sorry, I could not access your calendar. Please try re-authenticating.';
  }
};
```

### 7. Add Authentication UI

Update your `ControlTray.tsx` to add a "Connect Calendar" button:

```typescript
import { oauthManager } from '../lib/oauth-manager';

function ControlTray() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);

  useEffect(() => {
    setIsAuthenticated(oauthManager.isAuthenticated());
  }, []);

  const handleConnect = async () => {
    await oauthManager.authenticate();
  };

  return (
    <div className="control-tray">
      {/* ... existing controls ... */}
      
      {!isAuthenticated && (
        <button onClick={handleConnect}>
          Connect Calendar
        </button>
      )}
      
      {isAuthenticated && (
        <div>
          ✅ Calendar Connected
          <button onClick={() => oauthManager.logout()}>
            Disconnect
          </button>
        </div>
      )}
    </div>
  );
}
```

## Function-Calling Flow with Personal Data

Here's how it works:

1. **User**: "What's on my calendar today?"
2. **Gemini**: Decides to call `getTodaysCalendarEvents`
3. **Your App**: 
   - Checks if user is authenticated
   - If not, tells Gemini to inform user
   - If yes, calls Google Calendar API
   - Returns real events
4. **Gemini**: Uses that data to respond to user

## Security Considerations

1. **Never expose Client Secret**: Keep it server-side only
2. **Token Storage**: Use secure storage (consider httpOnly cookies for production)
3. **Scopes**: Request only the minimum permissions needed
4. **Token Refresh**: Implement automatic token refresh (Google tokens expire)
5. **HTTPS**: Always use HTTPS in production (OAuth requires it)

## Adding More Personal Data Functions

Once OAuth is set up, you can add more functions:

### Gmail Function

```typescript
const checkRecentEmails: ToolImplementation = async (args, context) => {
  const auth = oauthManager.getAuth();
  const gmail = google.gmail({ version: 'v1', auth });

  const response = await gmail.users.messages.list({
    userId: 'me',
    maxResults: 5,
  });

  // Process email data...
  return emailSummaries;
};
```

### Drive Function

```typescript
const searchDriveFiles: ToolImplementation = async (args, context) => {
  const auth = oauthManager.getAuth();
  const drive = google.drive({ version: 'v3', auth });

  const response = await drive.files.list({
    q: `name contains '${args.query}'`,
    fields: 'files(id, name, webViewLink)',
  });

  return JSON.stringify(response.data.files);
};
```

## Testing

1. Start dev server: `npm run dev`
2. Click "Connect Calendar"
3. Authenticate with Google
4. Say: "What's on my calendar?"
5. Gemini will call the real function

## Next Steps

1. Implement OAuth flow
2. Replace mock functions with real API calls
3. Add more personal data functions as needed
4. Test thoroughly
5. Deploy to production (remember HTTPS!)

