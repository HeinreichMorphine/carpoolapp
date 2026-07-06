# Carpool App Updates (July 7, 2026)

This document summarizes the backend and frontend updates pushed today. Teammates should pull the latest changes on the `main` branch and perform the required Supabase database updates described below.

---

## 🚀 Summary of Changes

### 1. Fix: Driver Accept Silent Disappearance
* **Issue:** When a driver clicked "Accept" on a ride offer, the card would appear for a second and then disappear.
* **Cause:** The Row Level Security (RLS) `UPDATE` policy on the `rides` table only allowed updates if the user was *already* the assigned `driver_id` or `rider_id`. Since new requests have a `NULL` driver, the update query was silently rejected by the database.
* **Fix:** Updated the RLS policy to allow updates if the ride status is `'requested'`.
* **Files Modified:** `supabase/volumes/db/init.sql`

### 2. Feature: SOS Emergency Contacts & Alerts
* **New Flow:** Clicking the **🚨 SOS Alert** button on active rides now checks if you have set an emergency contact.
  * If unset, it prompts you to set a name and number, which saves directly to your user profile in Supabase.
  * Tapping Send Alert dispatches a notification to the Telegram admin group, and then opens a dialog giving you options to send a pre-filled distress message (complete with your live Google Maps location coordinates and web tracking link) via **WhatsApp** or **SMS**.
* **Register Screen Update:** Added emergency contact name and phone input fields directly into the email sign-up form so riders can configure this during registration.
* **Files Modified:** `lib/screens/auth_screen.dart`, `lib/screens/home_screen.dart`, `supabase/volumes/db/init.sql`

### 3. UX: Preset Location Quick-Select
* **Rider Fallback:** Selecting a popular destination from the "Popular in Melaka" list will now automatically populate a fallback pickup location (e.g., Christ Church Melaka) if you do not have location services turned on. This instantly calculates the route, fare estimate, and displays the booking buttons for testing.
* **Driver Commute Preset Chips:** Added start and destination quick-select chips to the driver's commute route panel. Drivers can now set their start and end points with a single tap instead of searching via keyboard.
* **Files Modified:** `lib/screens/home_screen.dart`

### 4. Architecture: Decoupled Driver Earnings
* **Concept:** Separates what the rider pays from what the driver earns (standard ride-share design).
* **Rider Pays:** Their locked-in, direct-route fare (includes the 20% or 30% carpool discount if shared).
* **Driver Earns:** Calculated based on the *actual* combined multi-stop route driven (calculated upon completing the final passenger's ride):
  $$\text{Driver Earnings} = 5.00 + (\text{Actual Total km} \times 1.20) + (\text{Actual Total mins} \times 0.30)$$
* **Automatic Credit:** Driver's wallet balance is automatically credited in Supabase when the carpool session ends.
* **Files Modified:** `lib/screens/home_screen.dart`

### 5. UI: Simplified Fare Details
* **Description:** Replaced the granular per-kilometer/minute line items on the Rider's active ride screen with a clean receipt card showing:
  * **Standard Direct Fare** (What the trip would cost if riding alone)
  * **Carpool Discount** (Green text showing the tier, e.g. `-20% Carpool Discount (2 Riders)`)
  * **Final Price Paid** (Final deducted wallet fare)
* **Files Modified:** `lib/screens/home_screen.dart`

---

## 🛠️ Required Action: Update Supabase Database

Since we updated table schemas and trigger functions, **please execute the following SQL script** in your [Supabase SQL Editor](https://supabase.com/dashboard/project/zwhyrnhhazjsciyyeijc):

```sql
-- 1. Add Emergency Contact Columns to Profiles
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS emergency_contact_name text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS emergency_contact_phone text;

-- 2. Update RLS Policy to allow drivers to accept unassigned requests
DROP POLICY IF EXISTS "Allow updates of self rides" ON public.rides;

CREATE POLICY "Allow updates of self rides" ON public.rides
  FOR UPDATE USING (
    auth.uid() = rider_id 
    OR auth.uid() = driver_id 
    OR status = 'requested'
  );

-- 3. Update User Signup Trigger to save emergency contact info
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (
    id, name, phone, role, wallet_balance, rating, is_online,
    emergency_contact_name, emergency_contact_phone
  )
  VALUES (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', new.email, new.phone, 'User'),
    new.phone,
    coalesce(new.raw_user_meta_data->>'role', 'rider'),
    0.0,
    5.0,
    false,
    new.raw_user_meta_data->>'emergency_contact_name',
    new.raw_user_meta_data->>'emergency_contact_phone'
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```
