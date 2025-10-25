/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
*/

import { GoogleGenAI, GenerateContentResponse } from '@google/genai';

/**
* Calls the Gemini API with the googleSearch tool to get a grounded response.
* @param prompt The user's text prompt.
* @returns An object containing the model's text response and grounding sources.
*/
export async function fetchMapsGroundedResponseSDK({
 prompt,
 apiKey,
 enableWidget = true,
 lat,
 lng,
 systemInstruction,
}: {
 prompt: string;
 apiKey: string;
 enableWidget?: boolean;
 lat?: number;
 lng?: number;
 systemInstruction?: string;
}): Promise<GenerateContentResponse> {
  if (!apiKey) {
    throw new Error('Missing required API Key.');
  }


  try {
    const ai = new GoogleGenAI({apiKey});
    const finalSystemInstruction =
      systemInstruction ?? "You are a helpful assistant that provides concise answers based on the user's query. Provide details for the top 3 results, unless the user requests less. Provide the name and a concise one line description that highlights a unique, interesting, or fun aspect about the place. Do not state addresses. ";

    const request: any = {
      model: 'gemini-2.5-flash',
      contents: prompt,
      config: {
        tools: [{googleMaps: {}}],
        thinkingConfig: {
          thinkingBudget: 0,
        },
        systemInstruction: finalSystemInstruction,
      },
    };


    if (lat !== undefined && lng !== undefined) {
      request.toolConfig = {
        retrievalConfig: {
          latLng: {
            latitude: lat,
            longitude: lng,
          },
        },
      };
    }


    const response = await ai.models.generateContent(request);
    return (response);
  } catch (error) {
    console.error(`Error calling Google Search grounding: ${error}
   With prompt: ${prompt}`);
    // Re-throw the error to be handled by the caller
    throw error;
  }
}


/**
* Calls the Google AI Platform REST API to get a Maps-grounded response.
* @param options The request parameters.
* @returns A promise that resolves to the API's GenerateContentResponse.
*/
export async function fetchMapsGroundedResponseREST({
 prompt,
 apiKey,
 enableWidget = true,
 lat,
 lng,
 systemInstruction,
}: {
 prompt: string;
 apiKey: string;
 enableWidget?: boolean;
 lat?: number;
 lng?: number;
 systemInstruction?: string;
}): Promise<GenerateContentResponse> {
  if (!apiKey) {
    throw new Error('Missing required API Key.');
  }
  const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent`;
  const finalSystemInstruction =
    systemInstruction ?? "You are a helpful assistant that provides concise answers based on the user's query. Provide details for the top 3 results, unless the user requests less. Provide the name and a concise one line description that highlights a unique, interesting, or fun aspect about the place. Do not state addresses. ";

  const requestBody: any = {
    contents: [
      {
        parts: [
          {
            text: prompt,
          },
        ],
      },
    ],
    system_instruction: {
        parts: [ { text: finalSystemInstruction } ]
    },
    tools: [
      {
        google_maps: {
         enable_widget: enableWidget
        },
      },
    ],
    generationConfig: {
       thinkingConfig: {
         thinkingBudget: 0
       }
     }
  };


  if (lat !== undefined && lng !== undefined) {
    requestBody.toolConfig = {
      retrievalConfig: {
        latLng: {
          latitude: lat,
          longitude: lng,
        },
      },
    };
  }


  try {
   //  console.log(`endpoint: ${endpoint}\nbody: ${JSON.stringify(requestBody, null, 2)}`)
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
      body: JSON.stringify(requestBody),
    });


    if (!response.ok) {
      const errorBody = await response.text();
      console.error('Error from Generative Language API:', errorBody);
      throw new Error(
        `API request failed with status ${response.status}: ${errorBody}`,
      );
    }


    const data = await response.json();
    return data as GenerateContentResponse;
  } catch (error) {
    console.error(`Error calling Maps grounding REST API: ${error}`);
    throw error;
  }
}