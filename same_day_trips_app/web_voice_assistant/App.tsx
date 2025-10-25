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
import React, {useCallback, useState, useEffect, useRef} from 'react';

import ControlTray from './components/ControlTray';
import ErrorScreen from './components/ErrorScreen';
import StreamingConsole from './components/streaming-console/StreamingConsole';
import PopUp from './components/popup/PopUp';
import Sidebar from './components/Sidebar';
import { LiveAPIProvider } from './contexts/LiveAPIContext';
import { APIProvider, useMapsLibrary, Map } from '@vis.gl/react-google-maps';
import { Map3D, Map3DCameraProps} from './components/map-3d';
import { useMapStore, useLogStore } from './lib/state';
import { MapController } from './lib/map-controller';

// Use a single API key for all services as defined by the build configuration.
const API_KEY = "AIzaSyDqkT4UaAlYiPv6ElDA5T08925spmqcSMU";

if (typeof API_KEY !== 'string') {
  throw new Error(
    'Missing required environment variable: GEMINI_API_KEY is not set.'
  );
}

const INITIAL_VIEW_PROPS: Map3DCameraProps = {
  center: {
    lat: 41.8739368,
    lng: -87.6372648,
    altitude: 12000,
  },
  range: 15000,
  tilt: 10,
  heading: 0,
  roll: 0,
};

function AppComponent() {
  const [map3d, setMap3d] = useState<google.maps.maps3d.Map3DElement | null>(null);
  const [map2d, setMap2d] = useState<google.maps.Map | null>(null);
  const [mapController, setMapController] = useState<MapController | null>(null);
  const [isTrafficVisible, setIsTrafficVisible] = useState(false);
  const [last3dView, setLast3dView] = useState<Map3DCameraProps>(INITIAL_VIEW_PROPS);
  const [isFlying, setIsFlying] = useState(false);

  const placesLib = useMapsLibrary('places');
  const maps3dLib = useMapsLibrary('maps3d');
  const elevationLib = useMapsLibrary('elevation');
  const geocodingLib = useMapsLibrary('geocoding');

  const [geocoder, setGeocoder] = useState<google.maps.Geocoder | null>(null);
  const {markers, cameraTarget, setCameraTarget, preventAutoFrame} = useMapStore();
  const [padding, setPadding] = useState<[number, number, number, number]>([0.05, 0.05, 0.05, 0.35]);
  const [userLocation, setUserLocation] = useState<{lat: number, lng: number} | null>(null);
  const [isPopupVisible, setIsPopupVisible] = useState(true);

  const consolePanelRef = useRef<HTMLDivElement>(null);
  const controlTrayRef = useRef<HTMLElement>(null);
  const trafficLayerRef = useRef<google.maps.TrafficLayer | null>(null);

  useEffect(() => {
    if (geocodingLib) {
      setGeocoder(new geocodingLib.Geocoder());
    }
  }, [geocodingLib]);

  useEffect(() => {
    if (map3d && maps3dLib && elevationLib) {
      setMapController(new MapController({map: map3d, maps3dLib, elevationLib}));
    }
  }, [map3d, maps3dLib, elevationLib]);
  
  useEffect(() => {
    navigator.geolocation.getCurrentPosition(
      (position) => {
        const { latitude, longitude } = position.coords;
        const location = { lat: latitude, lng: longitude };
        setUserLocation(location);
        setCameraTarget({
          center: { ...location, altitude: 1000 },
          range: 5000,
          tilt: 45,
          heading: 0,
          roll: 0,
        });
      },
      (error) => {
        console.error("Geolocation error:", error);
        useLogStore.getState().addTurn({
          role: 'system',
          text: 'Could not get your location. Using a default starting point.',
          isFinal: true,
        });
      },
      { enableHighAccuracy: true }
    );
  }, [setCameraTarget]);

  useEffect(() => {
    if (!mapController || !cameraTarget) return;

    setIsFlying(true);
    mapController.flyTo(cameraTarget);
    
    const flightTime = 5000;
    const timeoutId = setTimeout(() => {
      setIsFlying(false);
      setCameraTarget(null);
    }, flightTime);

    return () => clearTimeout(timeoutId);
  }, [mapController, cameraTarget, setCameraTarget]);
  
  useEffect(() => {
    if (!mapController || markers.length === 0 || preventAutoFrame) return;
    mapController.frameEntities(markers, padding);
  }, [mapController, markers, padding, preventAutoFrame]);
  
  useEffect(() => {
    if (mapController) {
      mapController.clearMap();
      mapController.addMarkers(markers);
    }
  }, [mapController, markers]);

  useEffect(() => {
    const calculatePadding = () => {
      const consoleEl = consolePanelRef.current;
      const trayEl = controlTrayRef.current;
      const vh = window.innerHeight;
      const vw = window.innerWidth;

      if (!consoleEl || !trayEl) return;

      const isMobile = window.matchMedia('(max-width: 768px)').matches;
      
      const top = 0.05;
      const right = 0.05;
      let bottom = 0.05;
      let left = 0.05;

      if (!isMobile) {
          left = Math.max(left, (consoleEl.offsetWidth / vw) + 0.02);
          bottom = Math.max(bottom, (trayEl.offsetHeight / vh) + 0.02);
      }
      
      setPadding([top, right, bottom, left]);
    };

    const observer = new ResizeObserver(calculatePadding);
    if (consolePanelRef.current) observer.observe(consolePanelRef.current);
    if (controlTrayRef.current) observer.observe(controlTrayRef.current);
    window.addEventListener('resize', calculatePadding);
    
    calculatePadding();

    return () => {
      if (consolePanelRef.current) observer.unobserve(consolePanelRef.current);
      if (controlTrayRef.current) observer.unobserve(controlTrayRef.current);
      window.removeEventListener('resize', calculatePadding);
    };
  }, []);

  useEffect(() => {
    if (isTrafficVisible) {
      if (!trafficLayerRef.current) {
        trafficLayerRef.current = new google.maps.TrafficLayer();
      }
      trafficLayerRef.current.setMap(map2d);
    } else {
      if (trafficLayerRef.current) {
        trafficLayerRef.current.setMap(null);
      }
    }
  }, [isTrafficVisible, map2d]);

  const handleToggleTraffic = useCallback(() => {
    setIsTrafficVisible(v => !v);
  }, []);
  
  const handleCameraChange = useCallback((cameraProps: Map3DCameraProps) => {
    if (!isFlying) {
      setLast3dView(cameraProps);
    }
  }, [isFlying]);

  const rangeToZoom = (range: number) => {
    const a = 156543.03392;
    const b = 2;
    // The previous formula included an erroneous multiplier that caused
    // an excessively high zoom level. This has been removed.
    return Math.log2((a * document.body.clientHeight) / (range * b));
  };
  
  return (
    <LiveAPIProvider 
        apiKey={API_KEY} 
        map={map3d} 
        placesLib={placesLib} 
        elevationLib={elevationLib} 
        geocoder={geocoder} 
        padding={padding}
        userLocation={userLocation}>
      {isPopupVisible && <PopUp onClose={() => setIsPopupVisible(false)} />}
      <div className="streaming-console">
        <div className="map-panel">
          <Map3D
            ref={setMap3d}
            {...INITIAL_VIEW_PROPS}
            onCameraChange={handleCameraChange}
          />
          {isTrafficVisible && (
            <Map
              style={{position: 'absolute', top: 0, left: 0, width: '100%', height: '100%'}}
              ref={setMap2d}
              center={last3dView.center}
              zoom={rangeToZoom(last3dView.range)}
              disableDefaultUI={true}
              mapId={'roadmap'}
            />
          )}
          <ControlTray trayRef={controlTrayRef} onToggleTraffic={handleToggleTraffic} isTrafficVisible={isTrafficVisible} />
        </div>
        <div className="console-panel" ref={consolePanelRef}>
          <StreamingConsole />
        </div>
        <ErrorScreen />
        <Sidebar />
      </div>
    </LiveAPIProvider>
  );
}

export default function App() {
  return (
    <APIProvider
        version={'alpha'}
        apiKey={API_KEY}
        libraries={['places', 'maps3d', 'elevation', 'geocoding']}
        solutionChannel={'gmp_aistudio_itineraryapplet_v1.0.0'}>
      <AppComponent />
    </APIProvider>
  );
}