/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
*/

/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */
/**
 * Copyright 2024 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { GenerateContentResponse, GroundingChunk } from '@google/genai';
import { fetchMapsGroundedResponseREST } from '../maps-grounding';
import { MapMarker, useLogStore, useMapStore, useUI } from '../state';
import { lookAtWithPadding } from '../look-at';

/**
 * Context object containing shared resources and setters that can be passed
 * to any tool implementation.
 */
export interface ToolContext {
  apiKey: string;
  map: google.maps.maps3d.Map3DElement | null;
  placesLib: google.maps.PlacesLibrary | null;
  elevationLib: google.maps.ElevationLibrary | null;
  geocoder: google.maps.Geocoder | null;
  padding: [number, number, number, number];
  userLocation: {lat: number; lng: number} | null;
  setHeldGroundedResponse: (
    response: GenerateContentResponse | undefined,
  ) => void;
  setHeldGroundingChunks: (chunks: GroundingChunk[] | undefined) => void;
}

/**
 * Defines the signature for any tool's implementation function.
 * @param args - The arguments for the function call, provided by the model.
 * @param context - The shared context object.
 * @returns A promise that resolves to either a string or a GenerateContentResponse
 *          to be sent back to the model.
 */
export type ToolImplementation = (
  args: any,
  context: ToolContext,
) => Promise<GenerateContentResponse | string>;

/**
 * Fetches and processes place details from grounding chunks.
 * @param groundingChunks - The grounding chunks from the model's response.
 * @param placesLib - The Google Maps Places library instance.
 * @param responseText - The model's text response to filter relevant places.
 * @param markerBehavior - Controls whether to show all markers or only mentioned ones.
 * @returns A promise that resolves to an array of MapMarker objects.
 */
async function fetchPlaceDetailsFromChunks(
  groundingChunks: GroundingChunk[],
  placesLib: google.maps.PlacesLibrary,
  responseText?: string,
  markerBehavior: 'mentioned' | 'all' | 'none' = 'mentioned',
): Promise<MapMarker[]> {
  if (markerBehavior === 'none' || !groundingChunks?.length) {
    return [];
  }

  let chunksToProcess = groundingChunks.filter(c => c.maps?.placeId);
  if (markerBehavior === 'mentioned' && responseText) {
    // Filter the marker list to only what was mentioned in the grounding text.
    chunksToProcess = chunksToProcess.filter(
      chunk =>
        chunk.maps?.title && responseText.includes(chunk.maps.title),
    );
  }

  if (!chunksToProcess.length) {
    return [];
  }

  const placesRequests = chunksToProcess.map(chunk => {
    const placeId = chunk.maps!.placeId.replace('places/', '');
    const place = new placesLib.Place({ id: placeId });
    return place.fetchFields({ fields: ['location', 'displayName'] });
  });

  const locationResults = await Promise.allSettled(placesRequests);

  const newMarkers: MapMarker[] = locationResults
    .map((result, index) => {
      if (result.status !== 'fulfilled' || !result.value.place.location) {
        return null;
      }
      
      const { place } = result.value;
      const originalChunk = chunksToProcess[index];
      
      let showLabel = true; // Default for 'mentioned'
      if (markerBehavior === 'all') {
        showLabel = !!(responseText && originalChunk.maps?.title && responseText.includes(originalChunk.maps.title));
      }

      return {
        position: {
          lat: place.location.lat(),
          lng: place.location.lng(),
          altitude: 1,
        },
        label: place.displayName ?? '',
        showLabel,
      };
    })
    .filter((marker): marker is MapMarker => marker !== null);

  return newMarkers;
}

/**
 * Updates the global map state based on the provided markers and grounding data.
 * It decides whether to perform a special close-up zoom or a general auto-frame.
 * @param markers - An array of markers to display on the map.
 * @param groundingChunks - The original grounding chunks to check for metadata.
 */
function updateMapStateWithMarkers(
  markers: MapMarker[],
  groundingChunks: GroundingChunk[],
) {
  const hasPlaceAnswerSources = groundingChunks.some(
    chunk => chunk.maps?.placeAnswerSources,
  );

  if (hasPlaceAnswerSources && markers.length === 1) {
    // Special close-up zoom: prevent auto-framing and set a direct camera target.
    const { setPreventAutoFrame, setMarkers, setCameraTarget } =
      useMapStore.getState();

    setPreventAutoFrame(true);
    setMarkers(markers);
    setCameraTarget({
      center: { ...markers[0].position, altitude: 200 },
      range: 500, // A tighter range for a close-up
      tilt: 60, // A steeper tilt for a more dramatic view
      heading: 0,
      roll: 0,
    });
  } else {
    // Default behavior: just set the markers and let the App component auto-frame them.
    const { setPreventAutoFrame, setMarkers } = useMapStore.getState();
    setPreventAutoFrame(false);
    setMarkers(markers);
  }
}


/**
 * Tool implementation for grounding queries with Google Maps.
 *
 * This tool fetches a grounded response and then, in a non-blocking way,
 * processes the place data to update the markers and camera on the 3D map.
 */
const mapsGrounding: ToolImplementation = async (args, context) => {
  const { apiKey, setHeldGroundedResponse, setHeldGroundingChunks, placesLib, userLocation } = context;
  const {
    query,
    markerBehavior = 'mentioned',
    systemInstruction,
    enableWidget,
  } = args;

  const groundedResponse = await fetchMapsGroundedResponseREST({
    prompt: query as string,
    apiKey,
    systemInstruction: systemInstruction as string | undefined,
    enableWidget: enableWidget as boolean | undefined,
    lat: userLocation?.lat,
    lng: userLocation?.lng,
  });

  if (!groundedResponse) {
    return 'Failed to get a response from maps grounding.';
  }

  // Hold response data for display in the chat log
  setHeldGroundedResponse(groundedResponse);
  const groundingChunks =
    groundedResponse?.candidates?.[0]?.groundingMetadata?.groundingChunks;
  if (groundingChunks && groundingChunks.length > 0) {
    setHeldGroundingChunks(groundingChunks);
  } else {
    // If there are no grounding chunks, clear any existing markers and return.
    useMapStore.getState().setMarkers([]);
    return groundedResponse;
  }

  // Process place details and update the map state asynchronously.
  // This is done in a self-invoking async function so that the `mapsGrounding`
  // tool can return the response to the model immediately without waiting for
  // the map UI to update.
  if (placesLib && markerBehavior !== 'none') {
    (async () => {
      try {
        const responseText =
          groundedResponse?.candidates?.[0]?.content?.parts?.[0]?.text;
        const markers = await fetchPlaceDetailsFromChunks(
          groundingChunks,
          placesLib,
          responseText,
          markerBehavior,
        );
        updateMapStateWithMarkers(markers, groundingChunks);
      } catch (e) {
        console.error('Error processing place details and updating map:', e);
      }
    })();
  } else if (markerBehavior === 'none') {
    // If no markers are to be created, ensure the map is cleared.
    useMapStore.getState().setMarkers([]);
  }

  return groundedResponse;
};

/**
 * Tool implementation for displaying a city on the 3D map.
 * This tool sets the `cameraTarget` in the global Zustand store. The main `App`
 * component has a `useEffect` hook that listens for changes to this state and
 * commands the `MapController` to fly to the new target.
 */
const frameEstablishingShot: ToolImplementation = async (args, context) => {
  let { lat, lng, geocode } = args;
  const { geocoder } = context;

  if (geocode && typeof geocode === 'string') {
    if (!geocoder) {
      const errorMessage = 'Geocoding service is not available.';
      useLogStore.getState().addTurn({
        role: 'system',
        text: errorMessage,
        isFinal: true,
      });
      return errorMessage;
    }
    try {
      const response = await geocoder.geocode({ address: geocode });
      if (response.results && response.results.length > 0) {
        const location = response.results[0].geometry.location;
        lat = location.lat();
        lng = location.lng();
      } else {
        const errorMessage = `Could not find a location for "${geocode}".`;
        useLogStore.getState().addTurn({
          role: 'system',
          text: errorMessage,
          isFinal: true,
        });
        return errorMessage;
      }
    } catch (error) {
      console.error(`Geocoding failed for "${geocode}":`, error);
      const errorMessage = `There was an error trying to find the location for "${geocode}". See browser console for details.`;
      useLogStore.getState().addTurn({
        role: 'system',
        text: errorMessage,
        isFinal: true,
      });
      return `There was an error trying to find the location for "${geocode}".`;
    }
  }

  if (typeof lat !== 'number' || typeof lng !== 'number') {
    return 'Invalid arguments for frameEstablishingShot. You must provide either a `geocode` string or numeric `lat` and `lng` values.';
  }

  // Instead of directly manipulating the map, we set a target in the global state.
  // The App component will observe this state and command the MapController to fly to the target.
  useMapStore.getState().setCameraTarget({
    center: { lat, lng, altitude: 5000 },
    range: 15000,
    tilt: 10,
    heading: 0,
    roll: 0,
  });

  if (geocode) {
    return `Set camera target to ${geocode}.`;
  }
  return `Set camera target to latitude ${lat} and longitude ${lng}.`;
};


/**
 * Tool implementation for framing a list of locations on the map. It can either
 * fly the camera to view the locations or add markers for them, letting the
 * main app's reactive state handle the camera framing.
 */
const frameLocations: ToolImplementation = async (args, context) => {
  const {
    locations: explicitLocations,
    geocode,
    markers: shouldCreateMarkers,
  } = args;
  const { elevationLib, padding, geocoder } = context;

  const locationsWithLabels: { lat: number; lng: number; label?: string }[] =
    [];

  // 1. Collect all locations from explicit coordinates and geocoded addresses.
  if (Array.isArray(explicitLocations)) {
    locationsWithLabels.push(
      ...(explicitLocations.map((loc: { lat: number; lng: number }) => ({
        ...loc,
      })) || []),
    );
  }

  if (Array.isArray(geocode) && geocode.length > 0) {
    if (!geocoder) {
      const errorMessage = 'Geocoding service is not available.';
      useLogStore
        .getState()
        .addTurn({ role: 'system', text: errorMessage, isFinal: true });
      return errorMessage;
    }

    const geocodePromises = geocode.map(address =>
      geocoder.geocode({ address }).then(response => ({ response, address })),
    );
    const geocodeResults = await Promise.allSettled(geocodePromises);

    geocodeResults.forEach(result => {
      if (result.status === 'fulfilled') {
        const { response, address } = result.value;
        if (response.results && response.results.length > 0) {
          const location = response.results[0].geometry.location;
          locationsWithLabels.push({
            lat: location.lat(),
            lng: location.lng(),
            label: address,
          });
        } else {
          const errorMessage = `Could not find a location for "${address}".`;
          useLogStore
            .getState()
            .addTurn({ role: 'system', text: errorMessage, isFinal: true });
        }
      } else {
        const errorMessage = `Geocoding failed for an address.`;
        console.error(errorMessage, result.reason);
        useLogStore
          .getState()
          .addTurn({ role: 'system', text: errorMessage, isFinal: true });
      }
    });
  }

  // 2. Check if we have any valid locations.
  if (locationsWithLabels.length === 0) {
    return 'Could not find any valid locations to frame.';
  }

  // 3. Perform the requested action.
  if (shouldCreateMarkers) {
    // Create markers and update the global state. The App component will
    // reactively frame these new markers.
    const markersToSet = locationsWithLabels.map((loc, index) => ({
      position: { lat: loc.lat, lng: loc.lng, altitude: 1 },
      label: loc.label || `Location ${index + 1}`,
      showLabel: true,
    }));

    const { setMarkers, setPreventAutoFrame } = useMapStore.getState();
    setPreventAutoFrame(false); // Ensure auto-framing is enabled
    setMarkers(markersToSet);

    return `Framed and added markers for ${markersToSet.length} locations.`;
  } else {
    // No markers requested. Clear existing markers and manually fly the camera.
    if (!elevationLib) {
      return 'Elevation library is not available.';
    }

    useMapStore.getState().clearMarkers();

    const elevator = new elevationLib.ElevationService();
    const cameraProps = await lookAtWithPadding(
      locationsWithLabels,
      elevator,
      0,
      padding,
    );

    useMapStore.getState().setCameraTarget({
      center: {
        lat: cameraProps.lat,
        lng: cameraProps.lng,
        altitude: cameraProps.altitude,
      },
      range: cameraProps.range + 1000,
      heading: cameraProps.heading,
      tilt: cameraProps.tilt,
      roll: 0,
    });

    return `Framed ${locationsWithLabels.length} locations on the map.`;
  }
};

/**
 * Tool implementation for getting directions from Google Maps.
 *
 * This tool constructs a Google Maps directions URL and opens it in a new tab.
 */
const getDirections: ToolImplementation = async (args, context) => {
  let {
    origin,
    destination,
    waypoints,
    travelMode = 'driving'
  } = args;
  const { userLocation } = context;
  const isCurrentLocation = /^(my location|current location|here|my position)$/i.test(origin);

  if (isCurrentLocation && userLocation) {
      origin = `${userLocation.lat},${userLocation.lng}`;
      useLogStore.getState().addTurn({
          role: 'system',
          text: `Using current location as origin: (${origin})`,
          isFinal: true,
      });
  } else if (isCurrentLocation && !userLocation) {
      return "I can't use your current location because you haven't granted permission or it's not available.";
  }

  if (!origin || !destination) {
    return 'Origin and destination are required to get directions.';
  }

  // Check if Google Maps is loaded
  if (typeof google === 'undefined' || !google.maps || !google.maps.DirectionsService) {
    return 'Google Maps is not loaded yet. Please try again in a moment.';
  }

  // Switch to 2D map mode (DirectionsService only works with 2D maps)
  if ((window as any).switchTo2DMap) {
    await (window as any).switchTo2DMap();
    useLogStore.getState().addTurn({
      role: 'system',
      text: `Switching to 2D map to show directions and traffic...`,
      isFinal: true,
    });
  }

  // Use DirectionsService to calculate the route
  const directionsService = new google.maps.DirectionsService();

  const request: google.maps.DirectionsRequest = {
    origin,
    destination,
    travelMode: travelMode.toUpperCase() as google.maps.TravelMode,
  };

  if (waypoints && Array.isArray(waypoints) && waypoints.length > 0) {
    request.waypoints = waypoints.map(wp => ({
      location: wp,
      stopover: true,
    }));
  }

  try {
    const response = await directionsService.route(request);

    if (response.status !== 'OK' || !response.routes || response.routes.length === 0) {
      return `I couldn't find a route from ${origin} to ${destination}. Status: ${response.status}`;
    }

    // Render the directions on the 2D map (map2d is returned from switchTo2DMap promise)
    // Note: switchTo2DMap was already awaited above, so map2d should be available
    const map2d = (window as any).getMap2D ? (window as any).getMap2D() : null;
    
    if (map2d) {
      // Create a new DirectionsRenderer or reuse existing one
      if (!(window as any).__directionsRenderer) {
        (window as any).__directionsRenderer = new google.maps.DirectionsRenderer({
          suppressMarkers: false,
          polylineOptions: {
            strokeColor: '#4285F4',
            strokeWeight: 5,
          }
        });
      }
      const directionsRenderer = (window as any).__directionsRenderer;
      directionsRenderer.setMap(map2d);
      directionsRenderer.setDirections(response);
      
      console.log('🗺️ Route rendered on 2D map');
      useLogStore.getState().addTurn({
        role: 'system',
        text: `Route displayed on the map`,
        isFinal: true,
      });
    } else {
      console.warn('2D map not available for rendering directions');
    }

    const route = response.routes[0];
    const leg = route.legs[0];
    const distance = leg.distance?.text || 'unknown distance';
    const duration = leg.duration?.text || 'unknown duration';

    // Build the navigation URL for the "Start Navigation" button
    const baseUrl = 'https://www.google.com/maps/dir/';
    const params = new URLSearchParams();
    params.append('api', '1');
    params.append('origin', origin);
    params.append('destination', destination);
    if (waypoints && Array.isArray(waypoints) && waypoints.length > 0) {
      params.append('waypoints', waypoints.join('|'));
    }
    params.append('travelmode', travelMode);
    const navUrl = `${baseUrl}?${params.toString()}`;

    // Store navigation data for the button
    (window as any).__navigationData = {
      destination,
      waypoints: waypoints && Array.isArray(waypoints) ? waypoints : [],
      url: navUrl,
    };

    // Store navigation launcher function for the floating button
    (window as any).__launchNavigation = () => {
      if ((window as any).FlutterNavigation) {
        (window as any).FlutterNavigation.postMessage(JSON.stringify({
          destination: destination,
          waypoints: waypoints || []
        }));
      } else {
        window.open(navUrl, '_blank');
      }
      // Hide button after launching
      if ((window as any).showNavigationButton) {
        (window as any).showNavigationButton(false);
      }
    };
    
    // Show the floating navigation button
    console.log('🔘 Attempting to show navigation button...');
    if ((window as any).showNavigationButton) {
      console.log('✅ showNavigationButton function exists, calling it');
      (window as any).showNavigationButton(true);
      console.log('✅ Navigation button should now be visible');
    } else {
      console.error('❌ showNavigationButton function not found on window');
    }

    return `Route found: ${distance}, ${duration}. The route is now displayed on the map with traffic information. Click the "Start Navigation" button on the map to launch turn-by-turn navigation in Google Maps.`;
  } catch (error) {
    console.error('Error getting directions:', error);
    return `An error occurred while getting directions: ${error}`;
  }
};

/**
 * Tool implementation for sending route to native navigation app.
 */
const sendToNavigation: ToolImplementation = async (args, context) => {
  const { destination, waypoints = [] } = args;
  
  // Build the navigation URL
  const baseUrl = 'https://www.google.com/maps/dir/';
  const params = new URLSearchParams();
  params.append('api', '1');
  params.append('destination', destination);
  if (waypoints && Array.isArray(waypoints) && waypoints.length > 0) {
    params.append('waypoints', waypoints.join('|'));
  }
  params.append('travelmode', 'driving');
  const navUrl = `${baseUrl}?${params.toString()}`;
  
  // Launch navigation
  if ((window as any).FlutterNavigation) {
    (window as any).FlutterNavigation.postMessage(JSON.stringify({
      destination: destination,
      waypoints: waypoints
    }));
    return `Navigation launched! Opening Google Maps to navigate to ${destination}.`;
  } else {
    window.open(navUrl, '_blank');
    return `Opening Google Maps in a new tab to navigate to ${destination}.`;
  }
};

/**
 * Tool implementation for adding a calendar event.
 */
const addCalendarEvent: ToolImplementation = async (args, context) => {
  const { title, startTime, endTime, location, description } = args;
  
  console.log('📅 Adding calendar event:', { title, startTime, endTime, location, description });
  
  // Validate ISO 8601 format
  const startDate = new Date(startTime);
  const endDate = new Date(endTime);
  
  if (isNaN(startDate.getTime()) || isNaN(endDate.getTime())) {
    return `I couldn't add the event because the time format is invalid. Please provide times in ISO 8601 format (e.g., "2025-10-28T14:00:00").`;
  }
  
  if (endDate <= startDate) {
    return `I couldn't add the event because the end time must be after the start time.`;
  }
  
  // Send to Flutter via JavaScript channel
  if ((window as any).FlutterCalendar) {
    try {
      const eventData = {
        title: title,
        startTime: startTime,
        endTime: endTime,
        location: location || '',
        description: description || ''
      };
      
      (window as any).FlutterCalendar.postMessage(JSON.stringify(eventData));
      
      // Format the time for user-friendly confirmation
      const startTimeFormatted = startDate.toLocaleString('en-US', {
        weekday: 'short',
        month: 'short',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
        hour12: true
      });
      
      let confirmMessage = `I've added "${title}" to your calendar on ${startTimeFormatted}`;
      if (location) {
        confirmMessage += ` at ${location}`;
      }
      confirmMessage += '.';
      
      return confirmMessage;
    } catch (error) {
      console.error('❌ Error adding calendar event:', error);
      return `I encountered an error while trying to add the event to your calendar. Please try again.`;
    }
  } else {
    // Fallback for web browser (not in Flutter WebView)
    console.warn('⚠️ FlutterCalendar not available, running in web browser');
    return `Calendar integration is only available in the mobile app. The event details are: "${title}" from ${startTime} to ${endTime}${location ? ` at ${location}` : ''}.`;
  }
};

/**
 * Tool implementation for checking the user's (mock) calendar.
 */
const getTodaysCalendarEvents: ToolImplementation = async (args, context) => {
  // In a real application, this would involve an OAuth flow and a call to the Google Calendar API.
  // For this demo, we'll return a hardcoded list of mock events to simulate the functionality.
  const mockEvents = [
    { summary: 'Morning Coffee & Planning', start: '09:00 AM', end: '09:30 AM' },
    { summary: 'Dentist Appointment', start: '2:00 PM', end: '3:00 PM' },
    { summary: 'Pick up groceries', start: '5:30 PM', end: '6:00 PM' },
  ];

  useLogStore.getState().addTurn({
    role: 'system',
    text: `Tool \`getTodaysCalendarEvents\` called.
Response:
\`\`\`json
${JSON.stringify(mockEvents, null, 2)}
\`\`\``,
    isFinal: true,
  });

  // We return the events as a JSON string for the model to process.
  return JSON.stringify(mockEvents);
};

/**
 * Tool implementation for getting real-time travel time from Google Maps Directions API.
 */
const getTravelTime: ToolImplementation = async (args, context) => {
  let { origin, destination, travelMode = 'driving' } = args;
  const { userLocation } = context;
  const isCurrentLocation = /^(my location|current location|here|my position)$/i.test(origin);

  if (isCurrentLocation && userLocation) {
      origin = `${userLocation.lat},${userLocation.lng}`;
      useLogStore.getState().addTurn({
          role: 'system',
          text: `Using current location as origin for travel time: (${origin})`,
          isFinal: true,
      });
  } else if (isCurrentLocation && !userLocation) {
      return "I can't calculate travel time from your current location because you haven't granted permission or it's not available.";
  }

  if (!origin || !destination) {
    return 'Origin and destination are required to calculate travel time.';
  }

  // DirectionsService is part of core Google Maps API, no library needed
  if (typeof google === 'undefined' || !google.maps || !google.maps.DirectionsService) {
    const errorMessage = 'Google Maps is not loaded yet. Please try again in a moment.';
    console.error(errorMessage);
    useLogStore.getState().addTurn({
      role: 'system',
      text: errorMessage,
      isFinal: true,
    });
    return errorMessage;
  }

  const directionsService = new google.maps.DirectionsService();

  // Ensure locations include city/state for better geocoding
  // If origin/destination don't have a comma and aren't coordinates, append ", Charlotte, NC"
  const formatLocation = (loc: string): string => {
    // Check if it's already coordinates (lat,lng format)
    if (/^-?\d+\.?\d*\s*,\s*-?\d+\.?\d*$/.test(loc)) {
      return loc;
    }
    // If it already has city info (contains comma), use as-is
    if (loc.includes(',')) {
      return loc;
    }
    // Otherwise, append Charlotte, NC as default
    return `${loc}, Charlotte, NC`;
  };

  const formattedOrigin = formatLocation(origin);
  const formattedDestination = formatLocation(destination);

  console.log(`🗺️ getTravelTime: origin="${formattedOrigin}" destination="${formattedDestination}"`);

  const request: google.maps.DirectionsRequest = {
    origin: formattedOrigin,
    destination: formattedDestination,
    travelMode: travelMode.toUpperCase() as google.maps.TravelMode,
    drivingOptions: {
      departureTime: new Date(),
      trafficModel: 'bestguess',
    },
  };

  try {
    const response = await directionsService.route(request);

    if (response.status !== 'OK' || !response.routes || response.routes.length === 0) {
      console.warn(`⚠️ Directions API returned status: ${response.status}`);
      
      // Provide detailed explanation of what went wrong
      let explanation = `I couldn't calculate travel time because `;
      if (response.status === 'NOT_FOUND') {
        explanation += `I couldn't find one or both of these locations:\n- Origin: "${formattedOrigin}"\n- Destination: "${formattedDestination}"\n\nThis usually means the location name is too vague or doesn't have an address. Please ask the user for a more specific address or landmark.`;
      } else if (response.status === 'ZERO_RESULTS') {
        explanation += `there's no route available between "${formattedOrigin}" and "${formattedDestination}". They might be too far apart or inaccessible by the selected travel mode.`;
      } else {
        explanation += `of an issue with the directions service (Status: ${response.status}).`;
      }
      
      return explanation;
    }

    const leg = response.routes[0].legs[0];
    const duration = leg.duration_in_traffic || leg.duration;

    if (duration && duration.text) {
      return duration.text;
    } else {
      return 'Could not determine the travel time.';
    }
  } catch (error) {
    console.error('❌ Error calling Directions API via JS SDK:', error);
    // Provide a more helpful error message
    const errorMsg = (error as any)?.message || 'Unknown error';
    
    let explanation = `I couldn't calculate travel time. `;
    if (errorMsg.includes('NOT_FOUND') || errorMsg.includes('geocoded')) {
      explanation += `The problem is that I couldn't find one or both of these locations:\n- Origin: "${formattedOrigin}"\n- Destination: "${formattedDestination}"\n\nThis often happens when:\n1. A calendar event doesn't have a location/address\n2. The location name is too vague (e.g., just "Meeting" or "Conference")\n3. The address is incomplete\n\nPlease ask the user for a specific address like "123 Main St, Charlotte, NC" or a well-known landmark.`;
    } else {
      explanation += `Error details: ${errorMsg}`;
    }
    
    return explanation;
  }
};

/**
 * Tool implementation for getting a weather forecast from a live public API.
 */
const getWeatherForecast: ToolImplementation = async (args, context) => {
  const { location } = args;
  const { geocoder } = context;

  if (!location) {
    return 'A location is required to get the weather forecast.';
  }

  if (!geocoder) {
    const errorMessage = 'Geocoding service is not available to find the location for the weather forecast.';
    useLogStore.getState().addTurn({ role: 'system', text: errorMessage, isFinal: true });
    return errorMessage;
  }

  // 1. Geocode the location string to get coordinates
  let lat: number, lng: number;
  try {
    const response = await geocoder.geocode({ address: location });
    if (response.results && response.results.length > 0) {
      const geo_location = response.results[0].geometry.location;
      lat = geo_location.lat();
      lng = geo_location.lng();
    } else {
      const errorMessage = `Could not find a location for "${location}" to get the weather.`;
      useLogStore.getState().addTurn({ role: 'system', text: errorMessage, isFinal: true });
      return errorMessage;
    }
  } catch (error) {
    console.error(`Geocoding failed for "${location}":`, error);
    const errorMessage = `There was an error trying to find the location for "${location}" to get the weather.`;
    useLogStore.getState().addTurn({ role: 'system', text: errorMessage, isFinal: true });
    return errorMessage;
  }

  // 2. Fetch live weather data from the public weather.gov API
  try {
    // First, get the specific forecast grid URL for the coordinates
    const pointsResponse = await fetch(`https://api.weather.gov/points/${lat},${lng}`);
    if (!pointsResponse.ok) {
        if(pointsResponse.status === 404) {
            const errorMessage = `I could not retrieve weather data for ${location}. This service primarily covers locations in the United States.`;
            useLogStore.getState().addTurn({ role: 'system', text: errorMessage, isFinal: true });
            return errorMessage;
        }
        throw new Error(`Failed to fetch weather gridpoint. Status: ${pointsResponse.status}`);
    }
    const pointsData = await pointsResponse.json();
    const forecastUrl = pointsData.properties.forecast;

    if (!forecastUrl) {
      const errorMessage = `Could not find a weather forecast URL for ${location}.`;
      useLogStore.getState().addTurn({ role: 'system', text: errorMessage, isFinal: true });
      return errorMessage;
    }

    // Second, fetch the actual forecast from that URL
    const forecastResponse = await fetch(forecastUrl);
    if (!forecastResponse.ok) {
      throw new Error(`Failed to fetch weather forecast. Status: ${forecastResponse.status}`);
    }
    const forecastData = await forecastResponse.json();
    
    // Extract the most relevant forecast text
    const todaysForecast = forecastData.properties.periods[0];
    if (!todaysForecast || !todaysForecast.detailedForecast) {
        const errorMessage = `No detailed forecast is available for ${location} at this time.`;
        useLogStore.getState().addTurn({ role: 'system', text: errorMessage, isFinal: true });
        return errorMessage;
    }

    const forecast = todaysForecast.detailedForecast;
    
    useLogStore.getState().addTurn({
      role: 'system',
      text: `Tool \`getWeatherForecast\` for "${location}" called.
Response:
\`\`\`
${forecast}
\`\`\``,
      isFinal: true,
    });

    return forecast;

  } catch (error) {
    const errorMessage = `Sorry, I was unable to retrieve the live weather forecast for ${location} at this time.`;
    console.error('Error fetching weather data:', error);
    useLogStore.getState().addTurn({
      role: 'system',
      text: `${errorMessage} See browser console for details.`,
      isFinal: true,
    });
    return errorMessage;
  }
};


/**
 * Tool implementation for tracking flights via FlightAware API.
 * Uses Firebase Cloud Function proxy to avoid CORS issues.
 */
const trackFlight: ToolImplementation = async (args, context) => {
  const { flightNumber, date } = args;

  if (!flightNumber) {
    return 'Flight number is required to track a flight.';
  }

  // Clean up flight number (remove spaces, convert to uppercase)
  const cleanFlightNumber = (flightNumber as string).replace(/\s+/g, '').toUpperCase();

  try {
    // Use Firebase Cloud Function proxy instead of calling FlightAware directly
    const functionUrl = 'https://us-central1-samedaytrips.cloudfunctions.net/flightawareProxy';
    
    const response = await fetch(functionUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        flightNumber: cleanFlightNumber,
        start: date as string || undefined,
        end: date as string || undefined,
        maxPages: 1,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error('FlightAware API error:', response.status, errorText);

      if (response.status === 404) {
        return `Flight ${flightNumber} not found. Please check the flight number and try again.`;
      } else if (response.status === 401) {
        return `Authentication error with FlightAware API. Please check the API key configuration.`;
      } else {
        return `Error fetching flight data: ${response.status}. Please try again.`;
      }
    }

    const data = await response.json();

    if (!data.flights || data.flights.length === 0) {
      return `No flight information found for ${flightNumber}.`;
    }

    // Get the most recent flight
    const flight = data.flights[0];

    // Format the response
    let responseText = `Flight ${flight.ident || flightNumber}:\n\n`;

    // Route information
    if (flight.origin && flight.destination) {
      responseText += `Route: ${flight.origin.code_icao || flight.origin.code_iata || flight.origin.code} → ${flight.destination.code_icao || flight.destination.code_iata || flight.destination.code}\n`;
    }

    // Status
    if (flight.status) {
      responseText += `Status: ${flight.status}\n`;
    }

    // Departure information
    if (flight.scheduled_out || flight.estimated_out || flight.actual_out) {
      responseText += `\nDeparture:\n`;
      if (flight.gate_origin) {
        responseText += `  Gate: ${flight.gate_origin}\n`;
      }
      if (flight.terminal_origin) {
        responseText += `  Terminal: ${flight.terminal_origin}\n`;
      }
      if (flight.scheduled_out) {
        const schedTime = new Date(flight.scheduled_out).toLocaleTimeString('en-US', {
          hour: 'numeric',
          minute: '2-digit',
          hour12: true
        });
        responseText += `  Scheduled: ${schedTime}\n`;
      }
      if (flight.estimated_out) {
        const estTime = new Date(flight.estimated_out).toLocaleTimeString('en-US', {
          hour: 'numeric',
          minute: '2-digit',
          hour12: true
        });
        responseText += `  Estimated: ${estTime}\n`;
      }
      if (flight.actual_out) {
        const actualTime = new Date(flight.actual_out).toLocaleTimeString('en-US', {
          hour: 'numeric',
          minute: '2-digit',
          hour12: true
        });
        responseText += `  Actual: ${actualTime}\n`;
      }
    }

    // Arrival information
    if (flight.scheduled_in || flight.estimated_in || flight.actual_in) {
      responseText += `\nArrival:\n`;
      if (flight.gate_destination) {
        responseText += `  Gate: ${flight.gate_destination}\n`;
      }
      if (flight.terminal_destination) {
        responseText += `  Terminal: ${flight.terminal_destination}\n`;
      }
      if (flight.scheduled_in) {
        const schedTime = new Date(flight.scheduled_in).toLocaleTimeString('en-US', {
          hour: 'numeric',
          minute: '2-digit',
          hour12: true
        });
        responseText += `  Scheduled: ${schedTime}\n`;
      }
      if (flight.estimated_in) {
        const estTime = new Date(flight.estimated_in).toLocaleTimeString('en-US', {
          hour: 'numeric',
          minute: '2-digit',
          hour12: true
        });
        responseText += `  Estimated: ${estTime}\n`;
      }
      if (flight.actual_in) {
        const actualTime = new Date(flight.actual_in).toLocaleTimeString('en-US', {
          hour: 'numeric',
          minute: '2-digit',
          hour12: true
        });
        responseText += `  Actual: ${actualTime}\n`;
      }
    }

    // Delay information
    if (flight.delay_minutes && flight.delay_minutes > 0) {
      responseText += `\n⚠️ Delayed by ${flight.delay_minutes} minutes\n`;
    }

    // Cancellation
    if (flight.cancelled) {
      responseText += `\n❌ This flight has been cancelled\n`;
    }

    useLogStore.getState().addTurn({
      role: 'system',
      text: `Tool \`trackFlight\` called for ${flightNumber}.`,
      isFinal: true,
    });

    return responseText;

  } catch (error) {
    console.error('Error calling FlightAware API:', error);
    const errorMessage = `Sorry, I was unable to retrieve flight information for ${flightNumber} at this time.`;
    useLogStore.getState().addTurn({
      role: 'system',
      text: `${errorMessage} See browser console for details.`,
      isFinal: true,
    });
    return errorMessage;
  }
};

/**
 * A registry mapping tool names to their implementation functions.
 * The `onToolCall` handler uses this to dispatch function calls dynamically.
 */
export const toolRegistry: Record<string, ToolImplementation> = {
  mapsGrounding,
  frameEstablishingShot,
  frameLocations,
  getDirections,
  sendToNavigation,
  addCalendarEvent,
  getTodaysCalendarEvents,
  getTravelTime,
  getWeatherForecast,
  trackFlight,
};