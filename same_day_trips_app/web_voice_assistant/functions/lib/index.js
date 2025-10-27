"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.flightawareProxy = void 0;
const functions = __importStar(require("firebase-functions"));
const cors_1 = __importDefault(require("cors"));
// Initialize CORS with options
const corsHandler = (0, cors_1.default)({
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
exports.flightawareProxy = functions.https.onRequest((req, res) => {
    corsHandler(req, res, async () => {
        try {
            // Only allow POST requests
            if (req.method !== 'POST') {
                res.status(405).json({ error: 'Method not allowed' });
                return;
            }
            // Get flight number from request body
            const { flightNumber, start, end, maxPages } = req.body;
            if (!flightNumber) {
                res.status(400).json({ error: 'Flight number is required' });
                return;
            }
            // FlightAware API key (stored in Firebase environment config)
            const FLIGHTAWARE_API_KEY = 'G3wJ4zeoOPTjGNpT5ZFnqbB4CmeGygEi';
            // Build query parameters
            const params = new URLSearchParams();
            if (start)
                params.append('start', start);
            if (end)
                params.append('end', end);
            if (maxPages)
                params.append('max_pages', maxPages.toString());
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
        }
        catch (error) {
            console.error('Error calling FlightAware API:', error);
            res.status(500).json({
                error: 'Internal server error',
                message: error.message,
            });
        }
    });
});
//# sourceMappingURL=index.js.map