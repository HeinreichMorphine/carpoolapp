// Deno Edge Function: match-driver
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.21.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    const { ride_id } = await req.json();

    if (!ride_id) {
      return new Response(
        JSON.stringify({ error: "Missing ride_id parameter" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 1. Get ride details
    const { data: ride, error: fetchError } = await supabaseClient
      .from("rides")
      .select("*")
      .eq("id", ride_id)
      .single();

    if (fetchError || !ride) {
      return new Response(
        JSON.stringify({ error: `Ride not found: ${fetchError?.message}` }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (ride.status !== "requested") {
      return new Response(
        JSON.stringify({ error: "Ride is already accepted or completed" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 2. Query for nearest online driver
    // Radius: 10km (10000 meters)
    const maxDistanceMeters = 10000;
    const { data: matchedDrivers, error: rpcError } = await supabaseClient.rpc(
      "find_nearest_driver",
      {
        pickup_lat: ride.pickup_latitude,
        pickup_lng: ride.pickup_longitude,
        max_dist_meters: maxDistanceMeters,
        target_women_only: ride.women_only
      }
    );

    if (rpcError) {
      return new Response(
        JSON.stringify({ error: `Driver lookup failed: ${rpcError.message}` }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!matchedDrivers || matchedDrivers.length === 0) {
      return new Response(
        JSON.stringify({ success: false, message: "No drivers available near the pickup point." }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const driver = matchedDrivers[0];

    // 3. Assign driver and update status
    const { error: updateError } = await supabaseClient
      .from("rides")
      .update({
        driver_id: driver.driver_id,
        status: "accepted",
        updated_at: new Date().toISOString()
      })
      .eq("id", ride_id);

    if (updateError) {
      return new Response(
        JSON.stringify({ error: `Failed to assign driver: ${updateError.message}` }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        driver_id: driver.driver_id,
        distance_meters: driver.distance,
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
