/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
*/
import { create } from 'zustand';
import {
  GenerateContentResponse,
  FunctionResponse,
  FunctionResponseScheduling,
  LiveServerToolCall,
  GroundingChunk,
} from '@google/genai';
import { Map3DCameraProps } from '../components/map-3d';
import { itineraryPlannerTools } from './tools/itinerary-planner';
import {
  getSystemInstructions,
  getScavengerHuntPrompt,
  getBusinessTripInstructions,
  getDefaultLiveApiModel,
  getDefaultVoice,
} from './constants';

export type Template = 'itinerary-planner';

export interface FunctionCall {
  name: string;
  description?: string;
  parameters?: any;
  isEnabled: boolean;
  scheduling?: FunctionResponseScheduling;
}

function getToolsets(): Record<Template, FunctionCall[]> {
  return {
    'itinerary-planner': itineraryPlannerTools,
  };
}

function getSystemPrompts(): Record<Template, string> {
  return {
    'itinerary-planner': getBusinessTripInstructions(),
  };
}

/**
 * Personas
 */
export function getScavengerHuntPersona(): string {
  return 'ClueMaster Cory, the Scavenger Hunt Creator';
}

export function getBusinessTripPersona(): string {
  return 'Business Travel Assistant';
}

export function getDefaultPersona(): string {
  return 'General Trip Planner';
}

export function getPersonas(): Record<string, { prompt: string; voice: string }> {
  return {
    [getBusinessTripPersona()]: {
      prompt: getBusinessTripInstructions(),
      voice: 'Charon', // Professional, informative voice
    },
    [getDefaultPersona()]: {
      prompt: getSystemInstructions(),
      voice: 'Zephyr', // Bright, friendly voice
    },
    [getScavengerHuntPersona()]: {
      prompt: getScavengerHuntPrompt(),
      voice: 'Puck', // Upbeat, playful voice
    },
  };
}

/**
 * Settings
 */
type SettingsStore = {
  systemPrompt: string;
  model: string;
  voice: string;
  isEasterEggMode: boolean;
  activePersona: string;
  setSystemPrompt: (prompt: string) => void;
  setModel: (model: string) => void;
  setVoice: (voice: string) => void;
  setPersona: (persona: string) => void;
  activateEasterEggMode: () => void;
};

export const useSettings = create<SettingsStore>(set => ({
  systemPrompt: getSystemPrompts()['itinerary-planner'],
  model: getDefaultLiveApiModel(),
  voice: 'Charon', // Professional voice for business mode
  isEasterEggMode: false,
  activePersona: getBusinessTripPersona(),
  setSystemPrompt: prompt => set({ systemPrompt: prompt }),
  setModel: model => set({ model }),
  setVoice: voice => set({ voice }),
  setPersona: (persona: string) => {
    const personas = getPersonas();
    if (personas[persona]) {
      set({
        activePersona: persona,
        systemPrompt: personas[persona].prompt,
        voice: personas[persona].voice,
      });
    }
  },
  activateEasterEggMode: () => {
    set(state => {
      if (!state.isEasterEggMode) {
        const personaName = getScavengerHuntPersona();
        const persona = getPersonas()[personaName];
        return {
          isEasterEggMode: true,
          activePersona: personaName,
          systemPrompt: persona.prompt,
          voice: persona.voice,
          model: 'gemini-live-2.5-flash-preview', // gemini-2.5-flash-preview-native-audio-dialog
        };
      }
      return {};
    });
  },
}));

/**
 * UI
 */
export const useUI = create<{
  isSidebarOpen: boolean;
  toggleSidebar: () => void;
  showSystemMessages: boolean;
  toggleShowSystemMessages: () => void;
}>(set => ({
  isSidebarOpen: false,
  toggleSidebar: () => set(state => ({ isSidebarOpen: !state.isSidebarOpen })),
  showSystemMessages: false,
  toggleShowSystemMessages: () =>
    set(state => ({ showSystemMessages: !state.showSystemMessages })),
}));

/**
 * Tools
 */
export const useTools = create<{
  tools: FunctionCall[];
  template: Template;
  setTemplate: (template: Template) => void;
}>(set => ({
  tools: getToolsets()['itinerary-planner'],
  template: 'itinerary-planner',
  setTemplate: (template: Template) => {
    set({ tools: getToolsets()[template], template });
    useSettings.getState().setSystemPrompt(getSystemPrompts()[template]);
  },
}));

/**
 * Logs
 */
export interface LiveClientToolResponse {
  functionResponses?: FunctionResponse[];
}
// FIX: Update GroundingChunk to match the type from @google/genai, where uri and title are optional.
// export interface GroundingChunk {
//   web?: {
//     uri?: string;
//     title?: string;
//   };
//   maps?: {
//     uri?: string;
//     title?: string;
//     placeId: string;
//     placeAnswerSources?: any;
//   };
// }

export interface ConversationTurn {
  timestamp: Date;
  role: 'user' | 'agent' | 'system';
  text: string;
  isFinal: boolean;
  toolUseRequest?: LiveServerToolCall;
  toolUseResponse?: LiveClientToolResponse;
  groundingChunks?: GroundingChunk[];
  toolResponse?: GenerateContentResponse;
}

export const useLogStore = create<{
  turns: ConversationTurn[];
  isAwaitingFunctionResponse: boolean;
  addTurn: (turn: Omit<ConversationTurn, 'timestamp'>) => void;
  updateLastTurn: (update: Partial<ConversationTurn>) => void;
  mergeIntoLastAgentTurn: (
    update: Omit<ConversationTurn, 'timestamp' | 'role'>,
  ) => void;
  clearTurns: () => void;
  setIsAwaitingFunctionResponse: (isAwaiting: boolean) => void;
}>((set, get) => ({
  turns: [],
  isAwaitingFunctionResponse: false,
  addTurn: (turn: Omit<ConversationTurn, 'timestamp'>) =>
    set(state => ({
      turns: [...state.turns, { ...turn, timestamp: new Date() }],
    })),
  updateLastTurn: (update: Partial<Omit<ConversationTurn, 'timestamp'>>) => {
    set(state => {
      if (state.turns.length === 0) {
        return state;
      }
      const newTurns = [...state.turns];
      const lastTurn = { ...newTurns[newTurns.length - 1], ...update };
      newTurns[newTurns.length - 1] = lastTurn;
      return { turns: newTurns };
    });
  },
  mergeIntoLastAgentTurn: (
    update: Omit<ConversationTurn, 'timestamp' | 'role'>,
  ) => {
    set(state => {
      const turns = state.turns;
      const lastAgentTurnIndex = turns.map(t => t.role).lastIndexOf('agent');

      if (lastAgentTurnIndex === -1) {
        // Fallback: add a new turn.
        return {
          turns: [
            ...turns,
            { ...update, role: 'agent', timestamp: new Date() } as ConversationTurn,
          ],
        };
      }

      const lastAgentTurn = turns[lastAgentTurnIndex];
      const mergedTurn: ConversationTurn = {
        ...lastAgentTurn,
        text: lastAgentTurn.text + (update.text || ''),
        isFinal: update.isFinal,
        groundingChunks: [
          ...(lastAgentTurn.groundingChunks || []),
          ...(update.groundingChunks || []),
        ],
        toolResponse: update.toolResponse || lastAgentTurn.toolResponse,
      };

      // Rebuild the turns array, replacing the old agent turn.
      const newTurns = [...turns];
      newTurns[lastAgentTurnIndex] = mergedTurn;


      return { turns: newTurns };
    });
  },
  clearTurns: () => set({ turns: [] }),
  setIsAwaitingFunctionResponse: isAwaiting =>
    set({ isAwaitingFunctionResponse: isAwaiting }),
}));

/**
 * Map Entities
 */
export interface MapMarker {
  position: {
    lat: number;
    lng: number;
    altitude: number;
  };
  label: string;
  showLabel: boolean;
  // Rich POI data from Google Places
  placeData?: {
    placeId?: string;
    address?: string;
    rating?: number;
    userRatingCount?: number;
    priceLevel?: string;
    phoneNumber?: string;
    website?: string;
    openingHours?: string;
    types?: string[];
  };
}

export const useMapStore = create<{
  markers: MapMarker[];
  cameraTarget: Map3DCameraProps | null;
  preventAutoFrame: boolean;
  setMarkers: (markers: MapMarker[]) => void;
  clearMarkers: () => void;
  setCameraTarget: (target: Map3DCameraProps | null) => void;
  setPreventAutoFrame: (prevent: boolean) => void;
}>(set => ({
  markers: [],
  cameraTarget: null,
  preventAutoFrame: false,
  setMarkers: markers => set({ markers }),
  clearMarkers: () => set({ markers: [] }),
  setCameraTarget: target => set({ cameraTarget: target }),
  setPreventAutoFrame: prevent => set({ preventAutoFrame: prevent }),
}));
