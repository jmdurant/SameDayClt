import * as functions from 'firebase-functions';
import cors from 'cors';
import {Request, Response} from 'express';

// Initialize CORS with options
const corsHandler = cors({
  origin: [
    'https://samedaytrips.web.app',
    'https://samedaytrips.firebaseapp.com',
    'http://localhost:5173', // For local development
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

        // FlightAware API key (stored in Firebase environment config)
        const FLIGHTAWARE_API_KEY = 'G3wJ4zeoOPTjGNpT5ZFnqbB4CmeGygEi';

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

