/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */
import { FunctionResponseScheduling } from '@google/genai';

export type Template = 'itinerary-planner';

export interface FunctionCall {
  name: string;
  description?: string;
  parameters?: any;
  isEnabled: boolean;
  scheduling?: FunctionResponseScheduling;
}
