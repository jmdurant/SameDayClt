/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
*/

import { FunctionCall } from '../types';
import { FunctionResponseScheduling } from '@google/genai';

export const itineraryPlannerTools: FunctionCall[] = [
  {
    name: 'mapsGrounding',
    description: `
    A versatile tool that leverages Google Maps data to generate contextual information and creative content about places. It can be used for two primary purposes:

    1.  **For Itinerary Planning:** Find and summarize information about places like restaurants, museums, or parks. Use a straightforward query to get factual summaries of top results.
        -   **Example Query:** "fun museums in Paris" or "best pizza in Brooklyn".

    2.  **For Creative Content:** Generate engaging narratives, riddles, or scavenger hunt clues based on real-world location data. Use a descriptive query combined with a custom 'systemInstruction' to guide the creative output.
        -   **Example Query:** "a famous historical restaurant in Paris".

    Args:
        query: A string describing the search parameters. You **MUST be as precise as possible**, include as much location data that you can such as city, state and/or country to reduce ambiguous results.
        markerBehavior: (Optional) Controls map markers. "mentioned" (default), "all", or "none".
        systemInstruction: (Optional) A string that provides a persona and instructions for the tool's output. Use this for creative tasks to ensure the response is formatted as a clue, riddle, etc.
        enableWidget: (Optional) A boolean to control whether the interactive maps widget is enabled for the response. Defaults to true. Set to false for simple text-only responses or when the UI cannot support the widget.

    Returns:
        A response from the maps grounding agent. The content and tone of the response will be shaped by the query and the optional 'systemInstruction'.
    `,
    parameters: {
      type: 'OBJECT',
      properties: {
        query: {
          type: 'STRING',
        },
        markerBehavior: {
          type: 'STRING',
          description:
            'Controls which results get markers. "mentioned" for places in the text response, "all" for all search results, or "none" for no markers.',
          enum: ['mentioned', 'all', 'none'],
        },
        systemInstruction: {
          type: 'STRING',
          description:
            "A string that provides a persona and instructions for the tool's output. Use this for creative tasks to ensure the response is formatted as a clue, riddle, etc.",
        },
        enableWidget: {
          type: 'BOOLEAN',
          description:
            'A boolean to control whether the interactive maps widget is enabled for the response. Defaults to true. Set to false for simple text-only responses or when the UI cannot support the widget.',
        },
      },
      required: ['query'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'frameEstablishingShot',
    description: 'Call this function to display a city or location on the map. Provide either a location name to geocode, or a specific latitude and longitude. This provides a wide, establishing shot of the area.',
    parameters: {
      type: 'OBJECT',
      properties: {
        geocode: {
          type: 'STRING',
          description: 'The name of the location to look up (e.g., "Paris, France"). You **MUST be as precise as possible**, include as much location data that you can such as city, state and/or country to reduce ambiguous results.'
        },
        lat: {
          type: 'NUMBER',
          description: 'The latitude of the location.'
        },
        lng: {
          type: 'NUMBER',
          description: 'The longitude of the location.'
        },
      },
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'frameLocations',
    description: 'Frames multiple locations on the map, ensuring all are visible. Provide either an array of location names to geocode, or an array of specific latitude/longitude points. Can optionally add markers for these locations. When relying on geocoding you **MUST be as precise as possible**, include as much location data that you can such as city, state and/or country to reduce ambiguous results.',
    parameters: {
      type: 'OBJECT',
      properties: {
        locations: {
          type: 'ARRAY',
          items: {
            type: 'OBJECT',
            properties: {
              lat: { type: 'NUMBER' },
              lng: { type: 'NUMBER' },
            },
            required: ['lat', 'lng'],
          },
        },
        geocode: {
          type: 'ARRAY',
          description: 'An array of location names to look up (e.g., ["Eiffel Tower", "Louvre Museum"]).',
          items: {
            type: 'STRING',
          },
        },
        markers: {
          type: 'BOOLEAN',
          description: 'If true, adds markers to the map for each location being framed.'
        }
      },
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'getDirections',
    description: 'Generates a Google Maps URL for navigation between specified locations and opens it in a new tab for the user. Use this when the user explicitly asks for directions. If the origin is described as "my location" or "current location", the tool will automatically use the user\'s detected physical location.',
    parameters: {
      type: 'OBJECT',
      properties: {
        origin: {
          type: 'STRING',
          description: 'The starting point for the directions. Can be an address, place name, or coordinates. Accepts "my location" to use the user\'s current position.'
        },
        destination: {
          type: 'STRING',
          description: 'The ending point for the directions. Can be an address, place name, or coordinates.'
        },
        waypoints: {
          type: 'ARRAY',
          description: 'An optional list of intermediate stops.',
          items: {
            type: 'STRING'
          }
        },
        travelMode: {
          type: 'STRING',
          description: 'The mode of travel.',
          enum: ['driving', 'walking', 'bicycling', 'transit'],
          default: 'driving'
        }
      },
      required: ['origin', 'destination'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'sendToNavigation',
    description: 'Sends the current route to the device\'s native Google Maps app for turn-by-turn navigation. ONLY call this when the user explicitly asks to "navigate", "take me there", "send to navigation", "launch navigation", or similar commands requesting actual navigation to start. This is different from showing directions on the map.',
    parameters: {
      type: 'OBJECT',
      properties: {
        destination: {
          type: 'STRING',
          description: 'The destination address or place name to navigate to.'
        },
        waypoints: {
          type: 'ARRAY',
          description: 'Optional intermediate stops along the route.',
          items: {
            type: 'STRING'
          }
        }
      },
      required: ['destination'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'makePhoneCall',
    description: 'Initiates a phone call to a business or person. Use this when the user explicitly asks to call a place (e.g., "call the restaurant", "phone them", "dial their number"). Do NOT use this proactively - only when the user requests it.',
    parameters: {
      type: 'OBJECT',
      properties: {
        phoneNumber: {
          type: 'STRING',
          description: 'The phone number to call in E.164 format or local format (e.g., "+1-704-555-1234" or "(704) 555-1234")'
        },
        placeName: {
          type: 'STRING',
          description: 'The name of the business or person being called (e.g., "Higher Grounds Coffee", "Fahrenheit Restaurant")'
        }
      },
      required: ['phoneNumber'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'addCalendarEvent',
    description: 'Adds a new event to the user\'s calendar. Use this when the user asks to schedule something, add an event, or when you suggest a time for an activity and they agree. Always confirm the details before adding.',
    parameters: {
      type: 'OBJECT',
      properties: {
        title: {
          type: 'STRING',
          description: 'The title/name of the event (e.g., "Coffee break", "Lunch at Blue Restaurant", "Flight to NYC")'
        },
        startTime: {
          type: 'STRING',
          description: 'Start time in ISO 8601 format (e.g., "2025-10-28T14:00:00"). Must include date and time.'
        },
        endTime: {
          type: 'STRING',
          description: 'End time in ISO 8601 format (e.g., "2025-10-28T15:00:00"). Must include date and time.'
        },
        location: {
          type: 'STRING',
          description: 'Optional location/address for the event (e.g., "Starbucks, 123 Main St, Charlotte, NC")'
        },
        description: {
          type: 'STRING',
          description: 'Optional notes or description for the event'
        }
      },
      required: ['title', 'startTime', 'endTime'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'getTodaysCalendarEvents',
    description: "Checks the user's calendar for today's events to help with planning. Call this at the beginning of the conversation to see if there are any existing plans to work around.",
    parameters: {
      type: 'OBJECT',
      properties: {},
      required: [],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'getTravelTime',
    description: 'Calculates the travel time between two locations, accounting for current traffic conditions. Use this to provide realistic travel estimates. If the origin is described as "my location" or "current location", the tool will automatically use the user\'s detected physical location.',
    parameters: {
      type: 'OBJECT',
      properties: {
        origin: {
          type: 'STRING',
          description: 'The starting point for the travel time calculation. Can be an address, place name, or "my location".'
        },
        destination: {
          type: 'STRING',
          description: 'The ending point for the travel time calculation. Can be an address or place name.'
        },
        travelMode: {
          type: 'STRING',
          description: 'The mode of travel.',
          enum: ['driving', 'walking', 'bicycling', 'transit'],
          default: 'driving'
        }
      },
      required: ['origin', 'destination'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'getWeatherForecast',
    description: 'Gets the current weather and a brief forecast for a specified location. Use this to provide context for activity planning, like suggesting indoor activities if it is raining.',
    parameters: {
      type: 'OBJECT',
      properties: {
        location: {
          type: 'STRING',
          description: 'The city and state, or city and country, for which to get the weather forecast (e.g., "Chicago, IL").'
        }
      },
      required: ['location'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'getCurrentTime',
    description: 'Gets the CURRENT time and date in the user\'s local timezone. Use this tool when you need to know the EXACT current time for time-sensitive queries like: checking if there is time before an appointment, calculating how much time until an event, determining what events are coming up next, or when the user explicitly asks "what time is it?". This always returns the most up-to-date time.',
    parameters: {
      type: 'OBJECT',
      properties: {},
      required: [],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'trackFlight',
    description: 'Gets real-time flight status including gate assignments, departure/arrival times, delays, and cancellations using FlightAware data. ONLY use this when the user explicitly provides a flight number or asks about a specific flight. Do NOT use this proactively or if no flight information is available.',
    parameters: {
      type: 'OBJECT',
      properties: {
        flightNumber: {
          type: 'STRING',
          description: 'The flight number to track (e.g., "AA1234" or "AA 1234"). Can include airline code and number.'
        },
        date: {
          type: 'STRING',
          description: 'Optional date of the flight in YYYY-MM-DD format. If not provided, will use today\'s date.'
        }
      },
      required: ['flightNumber'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'searchFlightsDuffel',
    description: 'Searches for round-trip flights between two airports using the Duffel API, which includes comprehensive airline coverage including Delta, American Airlines, and other major carriers. Returns detailed flight options with times, prices, carriers, and booking information. Use this when the user wants to search for flights between specific airports or needs alternative flight options beyond their booked flights.',
    parameters: {
      type: 'OBJECT',
      properties: {
        origin: {
          type: 'STRING',
          description: 'The 3-letter IATA airport code for the origin (e.g., "CLT", "ATL", "JFK")'
        },
        destination: {
          type: 'STRING',
          description: 'The 3-letter IATA airport code for the destination (e.g., "LAX", "ORD", "MIA")'
        },
        date: {
          type: 'STRING',
          description: 'Travel date in YYYY-MM-DD format. If not provided, defaults to tomorrow.'
        },
        departByHour: {
          type: 'NUMBER',
          description: 'Latest departure hour in 24-hour format (0-23). Default is 9 (9 AM).'
        },
        returnAfterHour: {
          type: 'NUMBER',
          description: 'Earliest return hour in 24-hour format (0-23). Default is 15 (3 PM).'
        },
        returnByHour: {
          type: 'NUMBER',
          description: 'Latest return hour in 24-hour format (0-23). Default is 19 (7 PM).'
        },
        maxDurationMinutes: {
          type: 'NUMBER',
          description: 'Maximum flight duration in minutes. Default is 240 (4 hours).'
        }
      },
      required: ['origin', 'destination'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'requestUber',
    description: 'Opens the Uber app to request or schedule a ride to a destination. Use this when the user specifically asks for Uber, or when they ask for a ride without specifying a service. The pickup location will automatically be set to the user\'s current location.',
    parameters: {
      type: 'OBJECT',
      properties: {
        destination: {
          type: 'STRING',
          description: 'The destination address or place name (e.g., "Charlotte Douglas Airport", "123 Main St, Charlotte, NC", "Bank of America Stadium")'
        },
        scheduledTime: {
          type: 'STRING',
          description: 'Optional scheduled pickup time in ISO 8601 format (e.g., "2025-10-30T06:00:00"). If not provided, requests an immediate ride.'
        },
        productType: {
          type: 'STRING',
          description: 'Optional ride type preference.',
          enum: ['uberX', 'uberXL', 'uberBlack', 'uberComfort'],
          default: 'uberX'
        },
        nickname: {
          type: 'STRING',
          description: 'Optional nickname for the ride (e.g., "Airport Transfer", "Morning Meeting")'
        }
      },
      required: ['destination'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'requestLyft',
    description: 'Opens the Lyft app to request or schedule a ride to a destination. Use this when the user specifically asks for Lyft. The pickup location will automatically be set to the user\'s current location.',
    parameters: {
      type: 'OBJECT',
      properties: {
        destination: {
          type: 'STRING',
          description: 'The destination address or place name (e.g., "Charlotte Douglas Airport", "123 Main St, Charlotte, NC", "Bank of America Stadium")'
        },
        scheduledTime: {
          type: 'STRING',
          description: 'Optional scheduled pickup time in ISO 8601 format (e.g., "2025-10-30T06:00:00"). If not provided, requests an immediate ride.'
        },
        rideType: {
          type: 'STRING',
          description: 'Optional ride type preference.',
          enum: ['lyft', 'lyft_plus', 'lyft_lux', 'lyft_luxsuv'],
          default: 'lyft'
        }
      },
      required: ['destination'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
];