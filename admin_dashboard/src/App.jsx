import React, { useState, useEffect } from 'react';
import { BrowserRouter, Routes, Route, useParams, Link } from 'react-router-dom';
import { createClient } from '@supabase/supabase-js';
import { MapContainer, TileLayer, Marker, Popup, Polyline, useMap } from 'react-leaflet';
import L from 'leaflet';
import { Shield, Users, AlertTriangle, Compass, MapPin, Check, Plus, Trash2 } from 'lucide-react';
import './index.css';

// Fix Leaflet Marker Icons in React
delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon-2x.png',
  iconUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png',
});

// Create custom car icon for driver tracking
const carIcon = new L.Icon({
  iconUrl: 'https://cdn-icons-png.flaticon.com/512/3202/3202926.png',
  iconSize: [36, 36],
  iconAnchor: [18, 18],
});

// Initialize Supabase Client
const supabaseUrl = 'http://localhost:8000';
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzgxMTU2MzU4LCJleHAiOjIwOTY1MTk5NTh9.NG09cBenuQ6omR9yXqHYfG39PEqPr3eY-h2yhvkxnHg';
const supabase = createClient(supabaseUrl, supabaseAnonKey);

// Custom helper to adjust map bounds dynamically
function RecenterMap({ points }) {
  const map = useMap();
  useEffect(() => {
    if (points && points.length > 0) {
      const bounds = L.latLngBounds(points);
      map.fitBounds(bounds, { padding: [50, 50] });
    }
  }, [points, map]);
  return null;
}

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<AdminDashboard />} />
        <Route path="/track/:rideId" element={<PublicLiveTrack />} />
      </Routes>
    </BrowserRouter>
  );
}

// --------------------------------------------------
// 1. ADMIN DASHBOARD PAGE
// --------------------------------------------------
function AdminDashboard() {
  const [activeTab, setActiveTab] = useState('map');
  const [rides, setRides] = useState([]);
  const [drivers, setDrivers] = useState([]);
  const [trustCircles, setTrustCircles] = useState([]);
  const [newDomain, setNewDomain] = useState('');
  const [newName, setNewName] = useState('');
  const [sosAlerts, setSosAlerts] = useState([]);

  useEffect(() => {
    fetchData();
    subscribeRealtime();
  }, []);

  const fetchData = async () => {
    // Fetch active rides
    const { data: activeRides } = await supabase
      .from('rides')
      .select('*')
      .neq('status', 'completed')
      .neq('status', 'cancelled');
    setRides(activeRides || []);

    // Fetch online drivers
    const { data: onlineDrivers } = await supabase
      .from('driver_locations')
      .select('*, profiles(name)');
    setDrivers(onlineDrivers || []);

    // Fetch trust circles
    const { data: domains } = await supabase
      .from('trust_circles')
      .select('*');
    setTrustCircles(domains || []);

    // Mock active SOS logs (rides with high fare or recent requested)
    const { data: allRides } = await supabase
      .from('rides')
      .select('*, profiles(name)')
      .order('created_at', { ascending: false })
      .limit(5);
    setSosAlerts(allRides || []);
  };

  const subscribeRealtime = () => {
    // Listen for ride updates
    supabase.channel('admin-rides')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'rides' }, () => {
        fetchData();
      })
      .subscribe();

    // Listen for driver GPS updates
    supabase.channel('admin-drivers')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'driver_locations' }, () => {
        fetchData();
      })
      .subscribe();
  };

  const handleAddDomain = async (e) => {
    e.preventDefault();
    if (!newDomain || !newName) return;
    const { error } = await supabase
      .from('trust_circles')
      .insert({ name: newName, domain: newDomain });
    if (!error) {
      setNewDomain('');
      setNewName('');
      fetchData();
    }
  };

  const handleDeleteDomain = async (id) => {
    await supabase.from('trust_circles').delete().eq('id', id);
    fetchData();
  };

  return (
    <div className="flex h-screen bg-gray-50 font-sans text-gray-900">
      {/* Sidebar */}
      <aside className="w-64 bg-black text-white flex flex-col justify-between p-6">
        <div>
          <div className="text-xl font-bold tracking-tight mb-8">JOMRIDE ADMIN</div>
          <nav className="space-y-2">
            <button
              onClick={() => setActiveTab('map')}
              className={`w-full flex items-center space-x-3 px-4 py-3 rounded-lg text-left transition ${
                activeTab === 'map' ? 'bg-zinc-800 text-white' : 'text-gray-400 hover:bg-zinc-900 hover:text-white'
              }`}
            >
              <Compass size={20} />
              <span>Live Monitor Map</span>
            </button>
            <button
              onClick={() => setActiveTab('rides')}
              className={`w-full flex items-center space-x-3 px-4 py-3 rounded-lg text-left transition ${
                activeTab === 'rides' ? 'bg-zinc-800 text-white' : 'text-gray-400 hover:bg-zinc-900 hover:text-white'
              }`}
            >
              <Users size={20} />
              <span>Active Trips ({rides.length})</span>
            </button>
            <button
              onClick={() => setActiveTab('trust')}
              className={`w-full flex items-center space-x-3 px-4 py-3 rounded-lg text-left transition ${
                activeTab === 'trust' ? 'bg-zinc-800 text-white' : 'text-gray-400 hover:bg-zinc-900 hover:text-white'
              }`}
            >
              <Shield size={20} />
              <span>Trust Circles</span>
            </button>
          </nav>
        </div>
        <div className="border-t border-zinc-800 pt-6">
          <div className="text-xs text-gray-500">System Version: v1.0.0 (Malaysia)</div>
        </div>
      </aside>

      {/* Main Content */}
      <main className="flex-1 flex flex-col overflow-hidden">
        {/* Header */}
        <header className="h-16 bg-white border-b flex items-center justify-between px-8">
          <h1 className="text-lg font-semibold capitalize">{activeTab} panel</h1>
          <div className="flex items-center space-x-4">
            <span className="flex h-2.5 w-2.5 rounded-full bg-green-500 animate-pulse"></span>
            <span className="text-sm font-medium text-gray-600">Stack Live</span>
          </div>
        </header>

        {/* Tab Views */}
        <div className="flex-1 overflow-auto p-8">
          {activeTab === 'map' && (
            <div className="h-full flex flex-col space-y-6">
              {/* Map Box */}
              <div className="flex-1 rounded-2xl overflow-hidden border bg-white h-96 relative">
                <MapContainer center={[2.1944, 102.2492]} zoom={13} className="h-full w-full">
                  <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
                  
                  {/* Active Ride Markers */}
                  {rides.map(ride => (
                    <React.Fragment key={ride.id}>
                      <Marker position={[ride.pickup_latitude, ride.pickup_longitude]}>
                        <Popup>Pickup point for ride {ride.id.substring(0, 5)}</Popup>
                      </Marker>
                      <Marker position={[ride.drop_latitude, ride.drop_longitude]}>
                        <Popup>Destination for ride {ride.id.substring(0, 5)}</Popup>
                      </Marker>
                    </React.Fragment>
                  ))}

                  {/* Active Drivers Markers */}
                  {drivers.map(drv => (
                    <Marker key={drv.driver_id} position={[drv.latitude, drv.longitude]} icon={carIcon}>
                      <Popup>
                        <strong>Driver ID:</strong> {drv.driver_id.substring(0, 5)}<br/>
                        <strong>Name:</strong> {drv.profiles?.name || 'Driver'}<br/>
                        <strong>Heading:</strong> {drv.heading}°
                      </Popup>
                    </Marker>
                  ))}
                </MapContainer>
              </div>

              {/* Mini Logs */}
              <div className="grid grid-cols-2 gap-6">
                <div className="bg-white p-6 rounded-2xl border">
                  <h3 className="font-bold mb-4 flex items-center space-x-2">
                    <Shield size={18} className="text-blue-500" />
                    <span>Active Drivers Monitoring</span>
                  </h3>
                  <div className="space-y-3">
                    {drivers.map(drv => (
                      <div key={drv.driver_id} className="flex justify-between items-center text-sm">
                        <span>{drv.profiles?.name || 'Driver'}</span>
                        <span className="text-xs text-gray-500">lat: {drv.latitude.toFixed(4)}, lng: {drv.longitude.toFixed(4)}</span>
                      </div>
                    ))}
                    {drivers.length === 0 && <p className="text-sm text-gray-500">No drivers currently online.</p>}
                  </div>
                </div>
                <div className="bg-white p-6 rounded-2xl border border-red-100">
                  <h3 className="font-bold mb-4 flex items-center space-x-2 text-red-600">
                    <AlertTriangle size={18} />
                    <span>Emergency Alerts Log</span>
                  </h3>
                  <div className="space-y-3">
                    {rides.some(r => r.fare > 50) ? (
                      <div className="bg-red-50 text-red-700 p-3 rounded-lg text-sm flex justify-between items-center">
                        <span>🚨 Potential Over-fare / Long Route Alert detected</span>
                        <Link to={`/track/${rides.find(r => r.fare > 50).id}`} className="underline font-semibold text-xs">Track</Link>
                      </div>
                    ) : (
                      <p className="text-sm text-gray-500">No critical alerts detected in system.</p>
                    )}
                  </div>
                </div>
              </div>
            </div>
          )}

          {activeTab === 'rides' && (
            <div className="bg-white rounded-2xl border overflow-hidden">
              <table className="min-w-full divide-y divide-gray-200">
                <thead className="bg-gray-50">
                  <tr>
                    <th className="px-6 py-3 text-left text-xs font-semibold text-gray-500 uppercase">Trip ID</th>
                    <th className="px-6 py-3 text-left text-xs font-semibold text-gray-500 uppercase">From</th>
                    <th className="px-6 py-3 text-left text-xs font-semibold text-gray-500 uppercase">To</th>
                    <th className="px-6 py-3 text-left text-xs font-semibold text-gray-500 uppercase">Fare</th>
                    <th className="px-6 py-3 text-left text-xs font-semibold text-gray-500 uppercase">Status</th>
                    <th className="px-6 py-3 text-left text-xs font-semibold text-gray-500 uppercase">Action</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-200 text-sm">
                  {rides.map(ride => (
                    <tr key={ride.id}>
                      <td className="px-6 py-4 font-mono text-xs text-gray-500">{ride.id.substring(0, 8)}...</td>
                      <td className="px-6 py-4">{ride.pickup_address}</td>
                      <td className="px-6 py-4">{ride.drop_address}</td>
                      <td className="px-6 py-4">RM {Number(ride.fare).toFixed(2)}</td>
                      <td className="px-6 py-4">
                        <span className="px-2 py-1 rounded bg-black text-white text-xs font-semibold uppercase">{ride.status}</span>
                      </td>
                      <td className="px-6 py-4">
                        <Link to={`/track/${ride.id}`} className="text-blue-600 hover:underline font-medium">Track Live</Link>
                      </td>
                    </tr>
                  ))}
                  {rides.length === 0 && (
                    <tr>
                      <td colSpan="6" className="text-center py-8 text-gray-500">No active trips currently in progress.</td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          )}

          {activeTab === 'trust' && (
            <div className="max-w-2xl bg-white p-8 rounded-2xl border">
              <h3 className="font-bold text-lg mb-6">Verified Corporate Domains</h3>
              <form onSubmit={handleAddDomain} className="flex gap-4 mb-8">
                <input
                  type="text"
                  placeholder="Company Name (e.g. Intel)"
                  value={newName}
                  onChange={e => setNewName(e.target.value)}
                  className="flex-1 border px-4 py-2.5 rounded-lg focus:outline-none focus:ring-2 focus:ring-black"
                />
                <input
                  type="text"
                  placeholder="Domain (e.g. intel.com)"
                  value={newDomain}
                  onChange={e => setNewDomain(e.target.value)}
                  className="flex-1 border px-4 py-2.5 rounded-lg focus:outline-none focus:ring-2 focus:ring-black"
                />
                <button type="submit" className="bg-black text-white px-5 py-2.5 rounded-lg flex items-center space-x-2 font-medium hover:bg-zinc-800">
                  <Plus size={18} />
                  <span>Add</span>
                </button>
              </form>

              <div className="space-y-3">
                {trustCircles.map(tc => (
                  <div key={tc.id} className="flex justify-between items-center bg-gray-50 p-4 rounded-xl border">
                    <div>
                      <div className="font-semibold text-gray-800">{tc.name}</div>
                      <div className="text-sm text-gray-500">@{tc.domain}</div>
                    </div>
                    <button onClick={() => handleDeleteDomain(tc.id)} className="text-red-500 hover:text-red-700">
                      <Trash2 size={20} />
                    </button>
                  </div>
                ))}
                {trustCircles.length === 0 && <p className="text-gray-500 text-sm">No white-listed domains configured yet.</p>}
              </div>
            </div>
          )}
        </div>
      </main>
    </div>
  );
}

// --------------------------------------------------
// 2. PUBLIC LIVE RIDE TRACKING PAGE
// --------------------------------------------------
function PublicLiveTrack() {
  const { rideId } = useParams();
  const [ride, setRide] = useState(null);
  const [driverLoc, setDriverLoc] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchRideData();
  }, [rideId]);

  const fetchRideData = async () => {
    try {
      const { data: rideData, error } = await supabase
        .from('rides')
        .select('*')
        .eq('id', rideId)
        .single();
      
      if (error || !rideData) throw new Error("Ride not found");
      setRide(rideData);

      if (rideData.driver_id) {
        const { data: loc } = await supabase
          .from('driver_locations')
          .select('*')
          .eq('driver_id', rideData.driver_id)
          .single();
        if (loc) {
          setDriverLoc(L.latLng(loc.latitude, loc.longitude));
        }
        
        // Subscribe to driver GPS
        supabase.channel(`driver-gps-${rideData.driver_id}`)
          .on('postgres_changes', {
            event: '*',
            schema: 'public',
            table: 'driver_locations',
            filter: `driver_id=eq.${rideData.driver_id}`
          }, payload => {
            const rec = payload.newRecord;
            if (rec) {
              setDriverLoc(L.latLng(rec.latitude, rec.longitude));
            }
          })
          .subscribe();
      }

      // Subscribe to ride details
      supabase.channel(`public-ride-${rideId}`)
        .on('postgres_changes', {
          event: 'UPDATE',
          schema: 'public',
          table: 'rides',
          filter: `id=eq.${rideId}`
        }, payload => {
          setRide(payload.newRecord);
        })
        .subscribe();

    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="h-screen w-screen flex justify-center items-center bg-gray-50">
        <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-black"></div>
      </div>
    );
  }

  if (!ride) {
    return (
      <div className="h-screen w-screen flex flex-col justify-center items-center bg-gray-50 text-gray-700">
        <AlertTriangle size={48} className="text-red-500 mb-4" />
        <h2 className="text-xl font-bold">Trip link has expired or is invalid.</h2>
        <p className="text-sm mt-1">Please double-check the ride tracking URL.</p>
      </div>
    );
  }

  const pickupPoint = L.latLng(ride.pickup_latitude, ride.pickup_longitude);
  const dropPoint = L.latLng(ride.drop_latitude, ride.drop_longitude);
  const mapPoints = [pickupPoint, dropPoint];
  if (driverLoc) mapPoints.push(driverLoc);

  return (
    <div className="h-screen w-screen flex flex-col md:flex-row font-sans">
      {/* Map Side */}
      <div className="flex-1 h-60-pct md:h-full relative z-10">
        <MapContainer center={pickupPoint} zoom={14} className="h-full w-full">
          <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
          
          <Marker position={pickupPoint}>
            <Popup>Pickup Location</Popup>
          </Marker>
          <Marker position={dropPoint}>
            <Popup>Destination Location</Popup>
          </Marker>
          
          {driverLoc && (
            <Marker position={driverLoc} icon={carIcon}>
              <Popup>Driver's live location</Popup>
            </Marker>
          )}

          <RecenterMap points={mapPoints} />
        </MapContainer>
      </div>

      {/* Details Panel */}
      <div className="w-full md:w-[420px] bg-white border-l shadow-2xl flex flex-col justify-between p-8 relative z-20">
        <div>
          <div className="flex items-center justify-between mb-6">
            <span className="px-3 py-1.5 rounded-full bg-black text-white text-xs font-semibold uppercase tracking-wider">
              {ride.status}
            </span>
            <div className="text-sm font-semibold text-gray-500">Live Ride Tracking</div>
          </div>

          <h2 className="text-2xl font-extrabold tracking-tight mb-8">Heading to {ride.drop_address}</h2>
          
          <div className="space-y-6">
            <div className="flex items-start space-x-3">
              <MapPin className="text-green-600 mt-1 shrink-0" size={20} />
              <div>
                <div className="text-xs text-gray-400 font-semibold uppercase">Pickup Point</div>
                <div className="text-gray-800 text-sm font-medium mt-0.5">{ride.pickup_address}</div>
              </div>
            </div>

            <div className="flex items-start space-x-3">
              <MapPin className="text-red-600 mt-1 shrink-0" size={20} />
              <div>
                <div className="text-xs text-gray-400 font-semibold uppercase">Destination</div>
                <div className="text-gray-800 text-sm font-medium mt-0.5">{ride.drop_address}</div>
              </div>
            </div>
          </div>
        </div>

        <div className="border-t pt-8 mt-8 space-y-6">
          <div className="grid grid-cols-3 gap-4 text-center">
            <div className="bg-gray-50 p-4 rounded-xl border">
              <div className="text-xs text-gray-400 font-medium">Distance</div>
              <div className="text-lg font-bold text-gray-800 mt-1">{ride.distance_km} km</div>
            </div>
            <div className="bg-gray-50 p-4 rounded-xl border">
              <div className="text-xs text-gray-400 font-medium">ETA</div>
              <div className="text-lg font-bold text-gray-800 mt-1">{ride.duration_mins} min</div>
            </div>
            <div className="bg-gray-50 p-4 rounded-xl border">
              <div className="text-xs text-gray-400 font-medium">Fare</div>
              <div className="text-lg font-bold text-gray-800 mt-1">RM {Number(ride.fare).toFixed(2)}</div>
            </div>
          </div>

          <div className="text-xs text-center text-gray-400">
            Powered by JomRide. Shared via private tracking link.
          </div>
        </div>
      </div>
    </div>
  );
}

export default App;
