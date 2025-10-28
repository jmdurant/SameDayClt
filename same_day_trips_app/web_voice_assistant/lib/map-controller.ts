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

import { Map3DCameraProps } from '../components/map-3d';
import { lookAtWithPadding } from './look-at';
import { MapMarker } from './state';

type MapControllerDependencies = {
  map: google.maps.maps3d.Map3DElement;
  maps3dLib: google.maps.Maps3DLibrary;
  elevationLib: google.maps.ElevationLibrary;
};

/**
 * A controller class to centralize all interactions with the Google Maps 3D element.
 */
export class MapController {
  private map: google.maps.maps3d.Map3DElement;
  private maps3dLib: google.maps.Maps3DLibrary;
  private elevationLib: google.maps.ElevationLibrary;

  constructor(deps: MapControllerDependencies) {
    this.map = deps.map;
    this.maps3dLib = deps.maps3dLib;
    this.elevationLib = deps.elevationLib;
  }

  /**
   * Clears all child elements (like markers) from the map.
   */
  clearMap() {
    this.map.innerHTML = '';
  }

  /**
   * Adds a list of markers to the map.
   * @param markers - An array of marker data to be rendered.
   */
  addMarkers(markers: MapMarker[]) {
    for (const markerData of markers) {
      const marker = new this.maps3dLib.Marker3DInteractiveElement({
        position: markerData.position,
        altitudeMode: 'RELATIVE_TO_MESH',
        label: markerData.showLabel ? markerData.label : null,
        title: markerData.label,
        drawsWhenOccluded: true,
      });
      
      // Add click handler to show directions popup
      marker.addEventListener('gmp-click', () => {
        this.showMarkerPopup(markerData);
      });
      
      this.map.appendChild(marker);
    }
  }
  
  /**
   * Shows a popup for a marker with directions option
   * @param markerData - The marker data to show popup for
   */
  private showMarkerPopup(markerData: MapMarker) {
    // Store the selected marker for the directions function to use
    (window as any).__selectedMarker = markerData;
    
    // Create and show a visual popup on the map
    this.createInfoWindow(markerData);
    
    console.log(`🗺️ Marker clicked: ${markerData.label} at ${markerData.position.lat}, ${markerData.position.lng}`);
  }
  
  /**
   * Creates an info window popup for a marker
   * @param markerData - The marker data to display in the popup
   */
  private createInfoWindow(markerData: MapMarker) {
    // Remove any existing popup
    const existingPopup = document.getElementById('marker-info-popup');
    if (existingPopup) {
      existingPopup.remove();
    }
    
    // Create popup container - positioned in center of map (above POIs)
    const popup = document.createElement('div');
    popup.id = 'marker-info-popup';
    popup.style.cssText = `
      position: fixed;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      background: white;
      padding: 20px;
      border-radius: 16px;
      box-shadow: 0 8px 24px rgba(0,0,0,0.4);
      z-index: 1000;
      max-width: 320px;
      animation: popIn 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275);
    `;
    
    // Add animation keyframes
    if (!document.getElementById('popup-animations')) {
      const style = document.createElement('style');
      style.id = 'popup-animations';
      style.textContent = `
        @keyframes popIn {
          from { 
            transform: translate(-50%, -50%) scale(0.8); 
            opacity: 0; 
          }
          to { 
            transform: translate(-50%, -50%) scale(1); 
            opacity: 1; 
          }
        }
      `;
      document.head.appendChild(style);
    }
    
    // Popup content
    popup.innerHTML = `
      <div style="font-size: 16px; font-weight: 600; margin-bottom: 8px; color: #202124;">
        ${markerData.label}
      </div>
      <button id="get-directions-btn" style="
        width: 100%;
        padding: 10px;
        background: #1a73e8;
        color: white;
        border: none;
        border-radius: 8px;
        font-size: 14px;
        font-weight: 500;
        cursor: pointer;
        margin-bottom: 8px;
      ">
        Get Directions
      </button>
      <button id="close-popup-btn" style="
        width: 100%;
        padding: 10px;
        background: #f1f3f4;
        color: #5f6368;
        border: none;
        border-radius: 8px;
        font-size: 14px;
        font-weight: 500;
        cursor: pointer;
      ">
        Close
      </button>
    `;
    
    document.body.appendChild(popup);
    
    // Add event listeners
    const directionsBtn = document.getElementById('get-directions-btn');
    const closeBtn = document.getElementById('close-popup-btn');
    
    if (directionsBtn) {
      directionsBtn.addEventListener('click', () => {
        popup.remove();
        // Request directions via Gemini
        if ((window as any).sendMessageToGemini) {
          (window as any).sendMessageToGemini(
            `Get me directions to ${markerData.label} at ${markerData.position.lat}, ${markerData.position.lng}`
          );
        }
      });
    }
    
    if (closeBtn) {
      closeBtn.addEventListener('click', () => {
        popup.remove();
      });
    }
  }

  /**
   * Animate the camera to a specific set of camera properties.
   * @param cameraProps - The target camera position, range, tilt, etc.
   */
  flyTo(cameraProps: Map3DCameraProps) {
    this.map.flyCameraTo({
      durationMillis: 5000,
      endCamera: {
        center: {
          lat: cameraProps.center.lat,
          lng: cameraProps.center.lng,
          altitude: cameraProps.center.altitude,
        },
        range: cameraProps.range,
        heading: cameraProps.heading,
        tilt: cameraProps.tilt,
        roll: cameraProps.roll,
      },
    });
  }

  /**
   * Calculates the optimal camera view to frame a set of entities and animates to it.
   * @param entities - An array of entities to frame (must have a `position` property).
   * @param padding - The padding to apply around the entities.
   */
  async frameEntities(
    entities: { position: { lat: number; lng: number } }[],
    padding: [number, number, number, number],
  ) {
    if (entities.length === 0) return;

    const elevator = new this.elevationLib.ElevationService();
    const cameraProps = await lookAtWithPadding(
      entities.map(e => e.position),
      elevator,
      0, // heading
      padding,
    );

    this.flyTo({
      center: {
        lat: cameraProps.lat,
        lng: cameraProps.lng,
        altitude: cameraProps.altitude,
      },
      range: cameraProps.range + 1000, // Add a bit of extra range
      heading: cameraProps.heading,
      tilt: cameraProps.tilt,
      roll: 0,
    });
  }
}