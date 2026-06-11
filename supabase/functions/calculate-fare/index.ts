// Deno Edge Function: calculate-fare
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Malaysia Bounding Box bounds
const MALAYSIA_BOUNDS = {
  minLat: 0.8,
  maxLat: 7.5,
  minLng: 99.5,
  maxLng: 119.5,
};

function isInMalaysia(lat: number, lng: number): boolean {
  return lat >= MALAYSIA_BOUNDS.minLat && lat <= MALAYSIA_BOUNDS.maxLat &&
         lng >= MALAYSIA_BOUNDS.minLng && lng <= MALAYSIA_BOUNDS.maxLng;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { pickup_lat, pickup_lng, drop_lat, drop_lng } = await req.json();

    if (!pickup_lat || !pickup_lng || !drop_lat || !drop_lng) {
      return new Response(
        JSON.stringify({ error: "Missing coordinates parameters" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Validate boundaries
    if (!isInMalaysia(pickup_lat, pickup_lng) || !isInMalaysia(drop_lat, drop_lng)) {
      return new Response(
        JSON.stringify({ error: "Booking coordinates must be inside Malaysia boundaries." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Call OSRM inside docker network
    const osrmUrl = `http://osrm:5000/route/v1/driving/${pickup_lng},${pickup_lat};${drop_lng},${drop_lat}?overview=full&geometries=polyline`;
    
    let distanceKm = 0;
    let durationMins = 0;
    let polyline = "";

    try {
      const osrmRes = await fetch(osrmUrl);
      const osrmData = await osrmRes.json();
      
      if (osrmData.routes && osrmData.routes.length > 0) {
        const route = osrmData.routes[0];
        distanceKm = route.distance / 1000.0; // OSRM returns meters
        durationMins = route.duration / 60.0; // OSRM returns seconds
        polyline = route.geometry;
      } else {
        throw new Error("No route found by OSRM");
      }
    } catch (err) {
      console.warn("OSRM routing failed, falling back to Haversine straight-line distance:", err);
      // Fallback: Haversine distance
      const R = 6371; // Earth radius in km
      const dLat = (drop_lat - pickup_lat) * Math.PI / 180;
      const dLon = (drop_lng - pickup_lng) * Math.PI / 180;
      const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(pickup_lat * Math.PI / 180) * Math.cos(drop_lat * Math.PI / 180) *
                Math.sin(dLon / 2) * Math.sin(dLon / 2);
      const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
      distanceKm = R * c;
      durationMins = distanceKm * 1.5; // Estimate 1.5 minutes per km fallback
    }

    // Calculate RM Fare
    // Base: RM 5.00, distance: RM 1.20 / km, duration: RM 0.30 / min
    const baseFare = 5.00;
    const distanceFare = distanceKm * 1.20;
    const timeFare = durationMins * 0.30;
    const totalFare = Math.max(5.00, parseFloat((baseFare + distanceFare + timeFare).toFixed(2)));

    return new Response(
      JSON.stringify({
        distance_km: parseFloat(distanceKm.toFixed(2)),
        duration_mins: parseFloat(durationMins.toFixed(1)),
        fare: totalFare,
        polyline: polyline,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error: any) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
