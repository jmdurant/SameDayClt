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
import { MapMarker, useLogStore, useMapStore } from '../state';
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
  directionsLib: google.maps.DirectionsLibrary | null;
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

  const baseUrl = 'https://www.google.com/maps/dir/';
  const params = new URLSearchParams();
  params.append('api', '1');
  params.append('origin', origin);
  params.append('destination', destination);
  if (waypoints && Array.isArray(waypoints) && waypoints.length > 0) {
    params.append('waypoints', waypoints.join('|'));
  }
  params.append('travelmode', travelMode);
  
  const url = `${baseUrl}?${params.toString()}`;

  // This will open a new tab.
  window.open(url, '_blank');
  
  useLogStore.getState().addTurn({
    role: 'system',
    text: `Opening directions in new tab: ${url}`,
    isFinal: true,
  });

  return `I've opened the directions from ${origin} to ${destination} in a new tab for you.`;
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
  const { directionsLib, userLocation } = context;
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

  if (!directionsLib) {
    const errorMessage = 'Directions service is not available.';
    console.error(errorMessage);
    useLogStore.getState().addTurn({
      role: 'system',
      text: errorMessage,
      isFinal: true,
    });
    return errorMessage;
  }

  const directionsService = new directionsLib.DirectionsService();

  const request: google.maps.DirectionsRequest = {
    origin,
    destination,
    travelMode: travelMode.toUpperCase() as google.maps.TravelMode,
    drivingOptions: {
      departureTime: new Date(),
      trafficModel: 'bestguess',
    },
  };

  try {
    const response = await directionsService.route(request);

    if (response.status !== 'OK' || !response.routes || response.routes.length === 0) {
      return `I couldn't find a route from ${origin} to ${destination}. Status: ${response.status}`;
    }

    const leg = response.routes[0].legs[0];
    const duration = leg.duration_in_traffic || leg.duration;

    if (duration && duration.text) {
      return duration.text;
    } else {
      return 'Could not determine the travel time.';
    }
  } catch (error) {
    console.error('Error calling Directions API via JS SDK:', error);
    return 'There was an error calculating the travel time.';
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
 */
const trackFlight: ToolImplementation = async (args, context) => {
  const { flightNumber, date } = args;
  const FLIGHTAWARE_API_KEY = 'G3wJ4zeoOPTjGNpT5ZFnqbB4CmeGygEi';

  if (!flightNumber) {
    return 'Flight number is required to track a flight.';
  }

  // Clean up flight number (remove spaces, convert to uppercase)
  const cleanFlightNumber = (flightNumber as string).replace(/\s+/g, '').toUpperCase();

  try {
    // FlightAware AeroAPI v4 endpoint
    const apiUrl = `https://aeroapi.flightaware.com/aeroapi/flights/${cleanFlightNumber}`;

    const params = new URLSearchParams();
    if (date) {
      params.append('start', date as string);
      params.append('end', date as string);
    }
    params.append('max_pages', '1');

    const url = `${apiUrl}${params.toString() ? '?' + params.toString() : ''}`;

    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'x-apikey': FLIGHTAWARE_API_KEY,
        'Accept': 'application/json',
      },
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
  getTodaysCalendarEvents,
  getTravelTime,
  getWeatherForecast,
  trackFlight,
};