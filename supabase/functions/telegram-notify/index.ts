// Deno Edge Function: telegram-notify
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

    const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN");
    const adminChatId = Deno.env.get("TELEGRAM_ADMIN_CHAT_ID");

    if (!botToken || !adminChatId) {
      console.warn("Telegram bot credentials missing from server environment.");
      return new Response(
        JSON.stringify({ success: false, message: "Telegram keys are not configured in .env" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const body = await req.json();
    const { ride_id, status, details } = body;

    let messageText = "";

    if (status === "sos") {
      const { rider_name, latitude, longitude } = details;
      const adminTrackUrl = Deno.env.get("ADMIN_TRACK_URL") ?? "http://localhost:8080";
      const trackLink = `${adminTrackUrl}/track/${ride_id}`;
      messageText = `🚨 *SOS EMERGENCY ALERT* 🚨\n\n*Rider*: ${rider_name}\n*Location*: lat ${latitude}, lng ${longitude}\n\n[Track Live Trip in Browser](${trackLink})`;
    } else {
      // 1. Fetch ride details
      const { data: ride, error: fetchError } = await supabaseClient
        .from("rides")
        .select(`
          id,
          status,
          pickup_address,
          drop_address,
          fare,
          rider_id,
          driver_id
        `)
        .eq("id", ride_id)
        .single();

      if (fetchError || !ride) {
        return new Response(
          JSON.stringify({ error: `Ride lookup failed: ${fetchError?.message}` }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Fetch Rider Profile
      const { data: rider } = await supabaseClient
        .from("profiles")
        .select("name")
        .eq("id", ride.rider_id)
        .single();

      // Fetch Driver Profile (if assigned)
      let driverName = "Driver";
      if (ride.driver_id) {
        const { data: driver } = await supabaseClient
          .from("profiles")
          .select("name")
          .eq("id", ride.driver_id)
          .single();
        if (driver) driverName = driver.name;
      }

      const riderName = rider?.name ?? "Rider";

      switch (status) {
        case "requested":
          messageText = `🚗 *New Ride Requested*\n\n*Passenger*: ${riderName}\n*From*: ${ride.pickup_address}\n*To*: ${ride.drop_address}\n*Estimated Fare*: RM ${ride.fare}`;
          break;
        case "accepted":
          messageText = `✅ *Ride Accepted*\n\n*Driver* ${driverName} is on the way to pick up *Passenger* ${riderName}.`;
          break;
        case "arrived":
          messageText = `📍 *Driver Arrived*\n\nDriver ${driverName} has arrived at ${ride.pickup_address}.`;
          break;
        case "picked_up":
          messageText = `🏁 *Trip Started*\n\nPassenger ${riderName} is in the vehicle. Heading to ${ride.drop_address}.`;
          break;
        case "completed":
          messageText = `🎉 *Trip Completed*\n\nFare of RM ${ride.fare} has been successfully processed for ${riderName}.`;
          break;
        case "cancelled":
          messageText = `❌ *Ride Cancelled*\n\nRide request ${ride_id} has been cancelled.`;
          break;
        default:
          messageText = `ℹ️ *Ride Status Update*\n\nRide ${ride_id} changed status to: *${status}*.`;
          break;
      }
    }

    // Call Telegram Bot HTTP API
    const telegramUrl = `https://api.telegram.org/bot${botToken}/sendMessage`;
    const res = await fetch(telegramUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        chat_id: adminChatId,
        text: messageText,
        parse_mode: "Markdown",
      }),
    });

    const telegramResult = await res.json();

    return new Response(
      JSON.stringify({ success: telegramResult.ok, result: telegramResult }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error: any) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
