import * as functions from 'firebase-functions';
import cors from 'cors';
import {Request, Response} from 'express';
import * as dotenv from 'dotenv';

// Load environment variables from .env file
dotenv.config();

// Initialize CORS with options
const corsHandler = cors({
  origin: [
    'https://samedaytrips.web.app',
    'https://samedaytrips.firebaseapp.com',
    /^http:\/\/localhost(:\d+)?$/, // Allow any localhost port for development
  ],
  credentials: true,
});

/**
 * Firebase Cloud Function to proxy FlightAware API requests
 * This avoids CORS issues and keeps the API key secure on the backend
 */
export const flightawareProxy = functions.https.onRequest(
  (req: Request, res: Response) => {
    corsHandler(req, res, async () => {
      try {
        // Only allow POST requests
        if (req.method !== 'POST') {
          res.status(405).json({error: 'Method not allowed'});
          return;
        }

        // Get flight number from request body
        const {flightNumber, start, end, maxPages} = req.body;

        if (!flightNumber) {
          res.status(400).json({error: 'Flight number is required'});
          return;
        }

        // FlightAware API key (loaded from environment variables)
        const FLIGHTAWARE_API_KEY = process.env.FLIGHTAWARE_API_KEY || '';

        // Build query parameters
        const params = new URLSearchParams();
        if (start) params.append('start', start);
        if (end) params.append('end', end);
        if (maxPages) params.append('max_pages', maxPages.toString());

        // Call FlightAware API
        const apiUrl = `https://aeroapi.flightaware.com/aeroapi/flights/${flightNumber}?${params.toString()}`;

        const response = await fetch(apiUrl, {
          method: 'GET',
          headers: {
            'x-apikey': FLIGHTAWARE_API_KEY,
            'Accept': 'application/json',
          },
        });

        if (!response.ok) {
          const errorText = await response.text();
          console.error('FlightAware API error:', response.status, errorText);
          res.status(response.status).json({
            error: 'FlightAware API error',
            details: errorText,
          });
          return;
        }

        const data = await response.json();
        res.status(200).json(data);
      } catch (error: any) {
        console.error('Error calling FlightAware API:', error);
        res.status(500).json({
          error: 'Internal server error',
          message: error.message,
        });
      }
    });
  }
);

/**
 * Firebase Cloud Function to proxy Duffel API requests
 * This avoids CORS issues and keeps the API key secure on the backend
 */
export const duffelProxy = functions.https.onRequest(
  (req: Request, res: Response) => {
    corsHandler(req, res, async () => {
      try {
        // Only allow POST requests
        if (req.method !== 'POST') {
          res.status(405).json({error: 'Method not allowed'});
          return;
        }

        // Get parameters from request body
        const {
          origin,
          destination,
          date,
          returnDate, // Optional: defaults to same day for backward compatibility
          earliestDepartHour = 5,
          departByHour = 9,
          returnAfterHour = 15,
          returnByHour = 19,
          minDurationMinutes = 50,
          maxDurationMinutes = 240,
          allowedCarriers = [],
        } = req.body;

        // Use returnDate if provided, otherwise default to same day
        const actualReturnDate = returnDate || date;

        if (!origin || !destination) {
          res.status(400).json({
            error: 'Origin and destination are required',
          });
          return;
        }

        // Duffel API access token (loaded from environment variables)
        const DUFFEL_ACCESS_TOKEN = process.env.DUFFEL_ACCESS_TOKEN || '';

        if (!DUFFEL_ACCESS_TOKEN) {
          res.status(500).json({
            error: 'Duffel API token not configured',
            details: 'Please set DUFFEL_ACCESS_TOKEN in .env file'
          });
          return;
        }

        // Format time windows for Duffel (HH:MM format)
        const departFrom = `${earliestDepartHour.toString().padStart(2, '0')}:00`;
        const departTo = `${departByHour.toString().padStart(2, '0')}:00`;
        const returnFrom = `${returnAfterHour.toString().padStart(2, '0')}:00`;
        const returnTo = `${returnByHour.toString().padStart(2, '0')}:00`;

        // Normalize carrier filters to uppercase for matching
        const allowedCarrierSet = Array.isArray(allowedCarriers)
          ? allowedCarriers
              .map((c: string) => (c || '').toUpperCase())
              .filter((c: string) => c.length > 0)
          : [];

        // Call Duffel API for round-trip search
        const apiUrl = 'https://api.duffel.com/air/offer_requests';

        const response = await fetch(apiUrl, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${DUFFEL_ACCESS_TOKEN}`,
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Accept-Encoding': 'gzip',
            'Duffel-Version': 'v2',
          },
          body: JSON.stringify({
            data: {
              slices: [
                {
                  origin: origin,
                  destination: destination,
                  departure_date: date,
                  departure_time: {
                    from: departFrom,
                    to: departTo,
                  },
                },
                {
                  origin: destination, // Return flight
                  destination: origin,
                  departure_date: actualReturnDate, // Use separate return date for overnight trips
                  departure_time: {
                    from: returnFrom,
                    to: returnTo,
                  },
                },
              ],
              passengers: [
                {type: 'adult'},
              ],
              cabin_class: 'economy',
              max_connections: 1,
              return_offers: true,
            },
          }),
        });

        if (!response.ok) {
          const errorText = await response.text();
          console.error('Duffel API error:', response.status, errorText);
          res.status(response.status).json({
            error: 'Duffel API error',
            details: errorText,
          });
          return;
        }

        const data = await response.json();
        const offers = data.data?.offers || [];

        // Parse and filter offers
        const trips: any[] = [];
        for (const offer of offers) {
          const slices = offer.slices;
          if (slices.length !== 2) continue; // Must have outbound + return

          const outboundSlice = slices[0];
          const returnSlice = slices[1];

          // DEBUG: Log slice data to find "15:29" bug
          console.log('🔍 DEBUG SLICES:');
          console.log('  Outbound:', outboundSlice.origin, '→', outboundSlice.destination);
          console.log('  Return:', returnSlice.origin, '→', returnSlice.destination);
          if (returnSlice.segments && returnSlice.segments.length > 0) {
            console.log('  Return first segment departing_at:', returnSlice.segments[0].departing_at);
            console.log('  Return last segment arriving_at:', returnSlice.segments[returnSlice.segments.length - 1].arriving_at);
          }

          // Parse outbound flight
          const outbound = parseSlice(outboundSlice);
          const returnFlight = parseSlice(returnSlice);

          // DEBUG: Log parsed times
          if (outbound && returnFlight) {
            console.log('  Parsed outbound departTime:', outbound.departTime);
            console.log('  Parsed returnFlight departTime:', returnFlight.departTime);
          }

          if (!outbound || !returnFlight) continue;

          // Filter airlines if provided
          const matchesAllowed = (carriers: string[]) => {
            if (allowedCarrierSet.length === 0) return true;
            return carriers.some((c) => allowedCarrierSet.includes(c));
          };
          if (!matchesAllowed(outbound.carriers) ||
              !matchesAllowed(returnFlight.carriers)) {
            continue;
          }

          // Enforce home arrival window with minute precision (latest is inclusive of :00 only)
          const returnArrive = new Date(returnFlight.arriveTime);
          const arriveHour = returnArrive.getHours();
          const arriveMinute = returnArrive.getMinutes();
          const tooEarly = arriveHour < returnAfterHour;
          const tooLate = arriveHour > returnByHour ||
            (arriveHour === returnByHour && arriveMinute > 0);
          if (tooEarly || tooLate) {
            continue;
          }

          // Filter by duration
          if (outbound.durationMinutes < minDurationMinutes ||
              returnFlight.durationMinutes < minDurationMinutes) {
            continue;
          }

          if (outbound.durationMinutes > maxDurationMinutes ||
              returnFlight.durationMinutes > maxDurationMinutes) {
            continue;
          }

          // Get combined price
          const totalPrice = parseFloat(offer.total_amount);

          // Extract airline from first flight segment
          const firstSegment = offer.slices[0].segments[0];
          const airlineCode = firstSegment.operating_carrier?.iata_code ||
                             firstSegment.marketing_carrier?.iata_code ||
                             'XX';

          // Generate booking URLs
          const googleFlightsUrl = generateGoogleFlightsUrl(
            origin,
            destination,
            date,
            outbound.departTime,
            returnFlight.departTime
          );

          const kayakUrl = generateKayakUrl(
            origin,
            destination,
            date,
            outbound.departTime,
            returnFlight.departTime
          );

          const airlineUrl = generateAirlineUrl(
            airlineCode,
            origin,
            destination,
            date
          );

          trips.push({
            outbound,
            returnFlight,
            totalPrice,
            offerId: offer.id,
            airlineCode,
            googleFlightsUrl,
            kayakUrl,
            airlineUrl,
          });
        }

        // Return formatted response
        res.status(200).json({trips});
      } catch (error: any) {
        console.error('Error calling Duffel API:', error);
        res.status(500).json({
          error: 'Internal server error',
          message: error.message,
        });
      }
    });
  }
);

/**
 * Create a Duffel checkout link (keeps secret key on the server)
 */
export const createDuffelLink = functions.https.onRequest(
  (req: Request, res: Response) => {
    corsHandler(req, res, async () => {
      try {
        if (req.method !== 'POST') {
          res.status(405).json({error: 'Method not allowed'});
          return;
        }

        const {
          offerId,
          email,
          phoneNumber,
          givenName,
          familyName,
        } = req.body;

        if (!offerId) {
          res.status(400).json({error: 'offerId is required'});
          return;
        }

        const DUFFEL_ACCESS_TOKEN = process.env.DUFFEL_ACCESS_TOKEN || '';
        if (!DUFFEL_ACCESS_TOKEN) {
          res.status(500).json({
            error: 'Duffel API token not configured',
            details: 'Please set DUFFEL_ACCESS_TOKEN in .env file',
          });
          return;
        }

        const apiUrl = 'https://api.duffel.com/air/links';
        const passengers: any[] = [];
        if (email || phoneNumber || givenName || familyName) {
          passengers.push({
            type: 'adult',
            email,
            phone_number: phoneNumber,
            given_name: givenName,
            family_name: familyName,
          });
        }

        const body: any = {
          data: {
            offers: [offerId],
          },
        };
        if (passengers.length > 0) {
          body.data.passengers = passengers;
        }

        const response = await fetch(apiUrl, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${DUFFEL_ACCESS_TOKEN}`,
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Accept-Encoding': 'gzip',
            'Duffel-Version': 'v2',
          },
          body: JSON.stringify(body),
        });

        if (!response.ok) {
          const errorText = await response.text();
          console.error('Duffel link API error:', response.status, errorText);
          res.status(response.status).json({
            error: 'Duffel link API error',
            details: errorText,
          });
          return;
        }

        const data = await response.json();
        const linkUrl = data?.data?.url || data?.url || null;
        res.status(200).json({linkUrl});
      } catch (error: any) {
        console.error('Error creating Duffel link:', error);
        res.status(500).json({
          error: 'Internal server error',
          message: error.message,
        });
      }
    });
  }
);

/**
 * Helper function to parse a Duffel slice into our flight format
 */
function parseSlice(slice: any) {
  try {
    const segments = slice.segments;
    if (!segments || segments.length === 0) return null;

    const firstSegment = segments[0];
    const lastSegment = segments[segments.length - 1];

    // Parse times
    const departingAt = firstSegment.departing_at;
    const departTime = new Date(departingAt);

    const arrivingAt = lastSegment.arriving_at;
    const arriveTime = new Date(arrivingAt);

    // Duration
    const durationStr = slice.duration;
    const durationMinutes = parseDuration(durationStr) ||
        Math.floor((arriveTime.getTime() - departTime.getTime()) / 60000);

    // Flight numbers
    const flightNumbers = segments
      .map((seg: any) => {
        const operating = seg.operating_carrier;
        const marketing = seg.marketing_carrier;
        const carrier = operating?.iata_code || marketing?.iata_code || '??';
        const number = seg.operating_carrier_flight_number ||
                      seg.marketing_carrier_flight_number || '???';
        return `${carrier}${number}`;
      })
      .join(', ');

    const numStops = segments.length - 1;

    const carriers = segments
      .map((seg: any) => {
        const operating = seg.operating_carrier;
        const marketing = seg.marketing_carrier;
        return (operating?.iata_code || marketing?.iata_code || '').toUpperCase();
      })
      .filter((c: string) => c.length > 0);

    // Extract timezone offsets from ISO timestamps
    const departTzOffset = extractTimezoneOffset(departingAt);
    const arriveTzOffset = extractTimezoneOffset(arrivingAt);

    return {
      departTime: departTime.toISOString(),
      arriveTime: arriveTime.toISOString(),
      durationMinutes,
      flightNumbers,
      numStops,
      carriers,
      carrier: carriers[0] || null,
      departTimezoneOffset: departTzOffset,
      arriveTimezoneOffset: arriveTzOffset,
    };
  } catch (e) {
    console.error('Error parsing slice:', e);
    return null;
  }
}

/**
 * Helper function to parse ISO 8601 duration: "PT2H15M" -> 135 minutes
 */
function parseDuration(duration: string): number {
  if (!duration) return 0;

  let hours = 0;
  let minutes = 0;

  const hourMatch = duration.match(/(\d+)H/);
  const minMatch = duration.match(/(\d+)M/);

  if (hourMatch) {
    hours = parseInt(hourMatch[1], 10);
  }
  if (minMatch) {
    minutes = parseInt(minMatch[1], 10);
  }

  return hours * 60 + minutes;
}

/**
 * Generate Google Flights URL with specific times
 */
function generateGoogleFlightsUrl(
  origin: string,
  dest: string,
  date: string,
  outboundTime: string,
  returnTime: string
): string {
  // Round trip format: origin.dest.date*dest.origin.date
  const flightString = `${origin}.${dest}.${date}*${dest}.${origin}.${date}`;

  // Format times as HHMM (e.g., "0730" for 7:30 AM)
  const outboundDate = new Date(outboundTime);
  const returnDate = new Date(returnTime);

  const outboundHHMM = outboundDate.getHours().toString().padStart(2, '0') +
                       outboundDate.getMinutes().toString().padStart(2, '0');
  const returnHHMM = returnDate.getHours().toString().padStart(2, '0') +
                     returnDate.getMinutes().toString().padStart(2, '0');

  // Build URL with time filters
  return `https://www.google.com/flights?hl=en#flt=${flightString};c:USD;e:1;sd:1;t:f;tt:o;dep1:${outboundHHMM};dep2:${returnHHMM}`;
}

/**
 * Generate Kayak URL with specific times
 */
function generateKayakUrl(
  origin: string,
  dest: string,
  date: string,
  outboundTime: string,
  returnTime: string
): string {
  // Extract hour from time
  const outboundDate = new Date(outboundTime);
  const returnDate = new Date(returnTime);

  const outboundHour = outboundDate.getHours();
  const returnHour = returnDate.getHours();

  // Kayak uses time ranges in the URL (±2 hours from desired time)
  return `https://www.kayak.com/flights/${origin}-${dest}/${date}/${date}?sort=bestflight_a&fs=dep0=${outboundHour}00-${outboundHour + 2}00;dep1=${returnHour}00-${returnHour + 2}00`;
}

/**
 * Generate airline-specific booking URL
 */
function generateAirlineUrl(
  airlineCode: string,
  origin: string,
  dest: string,
  date: string
): string | null {
  // American Airlines award search
  if (airlineCode === 'AA') {
    const slice = encodeURIComponent(`{"orig":"${origin}","origNearby":false,"dest":"${dest}","destNearby":false,"date":"${date}"}`);
    return `https://www.aa.com/booking/search?locale=en_US&pax=1&adult=1&child=0&type=OneWay&searchType=Award&cabin=&carriers=ALL&slices=%5B${slice}%5D&maxAwardSegmentAllowed=2`;
  }

  // Delta direct booking
  if (airlineCode === 'DL') {
    return `https://www.delta.com/flight-search/book-a-flight?tripType=ROUND_TRIP&departureDate=${date}&returnDate=${date}&originCode=${origin}&destinationCode=${dest}&paxCount=1`;
  }

  // United direct booking
  if (airlineCode === 'UA') {
    return `https://www.united.com/en/us/fsr/choose-flights?f=${origin}&t=${dest}&d=${date}&r=${date}&px=1&taxng=1&idx=1`;
  }

  // Southwest direct booking
  if (airlineCode === 'WN') {
    return `https://www.southwest.com/air/booking/select.html?originationAirportCode=${origin}&destinationAirportCode=${dest}&departureDate=${date}&returnDate=${date}&adultPassengersCount=1`;
  }

  // JetBlue direct booking
  if (airlineCode === 'B6') {
    return `https://jetblue.com/booking/flights?from=${origin}&to=${dest}&depart=${date}&return=${date}&isMultiCity=false&noOfRoute=1&lang=en&adults=1`;
  }

  // For other airlines, return null (will use Google Flights/Kayak)
  return null;
}

/**
 * Extract timezone offset from ISO 8601 timestamp
 * Example: "2025-11-15T07:35:00-05:00" -> "-05:00"
 */
function extractTimezoneOffset(isoTimestamp: string): string | null {
  // ISO 8601 format: YYYY-MM-DDTHH:MM:SS±HH:MM
  // Offset starts at position 19
  if (isoTimestamp && isoTimestamp.length >= 25) {
    return isoTimestamp.substring(19); // e.g., "-05:00" or "+01:00"
  }
  return null;
}

