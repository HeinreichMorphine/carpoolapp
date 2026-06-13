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

    // Call OpenRouteService
    const orsKey = Deno.env.get("OPEN_ROUTE_SERVICE_API_KEY");
    let distanceKm = 0;
    let durationMins = 0;
    let polyline = "";

    try {
      if (!orsKey) throw new Error("OPEN_ROUTE_SERVICE_API_KEY missing");
      const orsUrl = `https://api.openrouteservice.org/v2/directions/driving-car?api_key=${orsKey}&start=${pickup_lng},${pickup_lat}&end=${drop_lng},${drop_lat}`;
      const orsRes = await fetch(orsUrl);
      if (!orsRes.ok) {
        throw new Error(`ORS API error: ${orsRes.statusText}`);
      }
      const orsData = await orsRes.json();
      
      if (orsData.features && orsData.features.length > 0) {
        const feature = orsData.features[0];
        const summary = feature.properties.summary;
        distanceKm = summary.distance / 1000.0; // ORS returns meters
        durationMins = summary.duration / 60.0; // ORS returns seconds
        
        // Encode coordinates to polyline string for flutter frontend compatibility
        const coords = feature.geometry.coordinates; // [lng, lat][]
        let prevLat = 0, prevLng = 0;
        for (const [lng, lat] of coords) {
          const latE5 = Math.round(lat * 1e5);
          const lngE5 = Math.round(lng * 1e5);
          let dLat = latE5 - prevLat;
          let dLng = lngE5 - prevLng;
          prevLat = latE5;
          prevLng = lngE5;
          dLat = dLat < 0 ? ~(dLat << 1) : (dLat << 1);
          dLng = dLng < 0 ? ~(dLng << 1) : (dLng << 1);
          while (dLat >= 0x20) {
            polyline += String.fromCharCode((0x20 | (dLat & 0x1f)) + 63);
            dLat >>= 5;
          }
          polyline += String.fromCharCode(dLat + 63);
          while (dLng >= 0x20) {
            polyline += String.fromCharCode((0x20 | (dLng & 0x1f)) + 63);
            dLng >>= 5;
          }
          polyline += String.fromCharCode(dLng + 63);
        }
      } else {
        throw new Error("No route found by ORS");
      }
    } catch (err) {
      console.warn("ORS routing failed, falling back to Haversine straight-line distance:", err);
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
