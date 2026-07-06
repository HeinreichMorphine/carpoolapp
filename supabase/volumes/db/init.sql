-- Enable PostGIS extension for geo-queries
create extension if not exists postgis schema public;
create extension if not exists "uuid-ossp" schema public;

-- --------------------------------------------------
-- Create Required Supabase Roles
-- --------------------------------------------------

-- 'anon' role: used by PostgREST for unauthenticated requests
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
end $$;

-- 'authenticator' role: PostgREST connects as this role and switches to anon/authenticated
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then
    create role authenticator noinherit login password 'postgres-carpool-secure-pass';
  end if;
end $$;

-- 'authenticated' role: used by PostgREST for authenticated requests
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
end $$;

-- 'service_role' role: bypasses RLS for server-side operations
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end $$;

-- 'supabase_auth_admin' role: used by GoTrue for auth schema management
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin noinherit login password 'postgres-carpool-secure-pass';
  end if;
end $$;

-- Grant role switching to authenticator
grant anon to authenticator;
grant authenticated to authenticator;
grant service_role to authenticator;

-- Grant schema usage
grant usage on schema public to anon, authenticated, service_role;
grant all on all tables in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;
grant all on all routines in schema public to anon, authenticated, service_role;

-- Default privileges for future tables
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant all on routines to anon, authenticated, service_role;

-- Auth schema permissions for GoTrue
grant all on schema auth to supabase_auth_admin;
grant all on all tables in schema auth to supabase_auth_admin;
grant all on all sequences in schema auth to supabase_auth_admin;
grant all on all routines in schema auth to supabase_auth_admin;

-- --------------------------------------------------
-- Create Tables
-- --------------------------------------------------

-- 1. Profiles Table (linked to auth.users)
create table if not exists public.profiles (
  id uuid references auth.users on delete cascade primary key,
  name text not null,
  phone text,
  avatar_url text,
  role text not null check (role in ('rider', 'driver', 'admin')),
  wallet_balance numeric(10, 2) not null default 0.00,
  rating numeric(3, 2) not null default 5.00,
  is_online boolean not null default false,
  gender text,
  corporate_email text,
  is_verified boolean not null default false,
  emergency_contact_name text,
  emergency_contact_phone text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

-- 2. Driver Locations Table (for realtime coordinates updates)
create table if not exists public.driver_locations (
  driver_id uuid references public.profiles(id) on delete cascade primary key,
  latitude double precision not null,
  longitude double precision not null,
  heading double precision not null default 0.0,
  updated_at timestamp with time zone not null default now()
);

-- 3. Rides Table
create table if not exists public.rides (
  id uuid primary key default uuid_generate_v4(),
  rider_id uuid references public.profiles(id) on delete cascade not null,
  driver_id uuid references public.profiles(id) on delete set null,
  status text not null check (status in ('requested', 'accepted', 'arrived', 'picked_up', 'completed', 'cancelled')),
  pickup_latitude double precision not null,
  pickup_longitude double precision not null,
  pickup_address text not null,
  drop_latitude double precision not null,
  drop_longitude double precision not null,
  drop_address text not null,
  distance_km numeric(6, 2) not null,
  duration_mins numeric(5, 1) not null,
  fare numeric(8, 2) not null,
  scheduled_at timestamp with time zone,
  women_only boolean not null default false,
  trust_circle_domain text,
  rating_rider integer check (rating_rider between 1 and 5),
  rating_driver integer check (rating_driver between 1 and 5),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

-- 4. Chats Table
create table if not exists public.chats (
  id uuid primary key default uuid_generate_v4(),
  ride_id uuid references public.rides(id) on delete cascade not null,
  sender_id uuid references public.profiles(id) on delete cascade not null,
  message text not null,
  created_at timestamp with time zone not null default now()
);

-- 5. Trust Circles Table
create table if not exists public.trust_circles (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  domain text not null unique,
  created_at timestamp with time zone not null default now()
);

-- --------------------------------------------------
-- Setup Database Functions
-- --------------------------------------------------

-- PostGIS helper to find the nearest online driver within radius
create or replace function public.find_nearest_driver(
  pickup_lat double precision, 
  pickup_lng double precision, 
  max_dist_meters double precision,
  target_women_only boolean default false
)
returns table (
  driver_id uuid,
  latitude double precision,
  longitude double precision,
  distance double precision
) as $$
begin
  return query
  select 
    dl.driver_id,
    dl.latitude,
    dl.longitude,
    st_distance(
      st_setsrid(st_point(dl.longitude, dl.latitude), 4326)::geography,
      st_setsrid(st_point(pickup_lng, pickup_lat), 4326)::geography
    ) as distance
  from public.driver_locations dl
  join public.profiles p on dl.driver_id = p.id
  where p.is_online = true
  and (not target_women_only or p.gender = 'female')
  and st_dwithin(
    st_setsrid(st_point(dl.longitude, dl.latitude), 4326)::geography,
    st_setsrid(st_point(pickup_lng, pickup_lat), 4326)::geography,
    max_dist_meters
  )
  order by distance asc
  limit 1;
end;
$$ language plpgsql security definer;

-- --------------------------------------------------
-- Setup Trigger for New Auth Users -> Profiles
-- --------------------------------------------------
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (
    id, name, phone, role, wallet_balance, rating, is_online,
    emergency_contact_name, emergency_contact_phone
  )
  values (
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
  return new;
end;
$$ language plpgsql security definer;

-- Trigger execution
create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- --------------------------------------------------
-- Row Level Security (RLS) & Policies
-- --------------------------------------------------

alter table public.profiles enable row level security;
alter table public.driver_locations enable row level security;
alter table public.rides enable row level security;
alter table public.chats enable row level security;
alter table public.trust_circles enable row level security;

-- Profiles Policies
create policy "Allow public read of profiles" on public.profiles
  for select using (true);

create policy "Allow updates to self profile" on public.profiles
  for update using (auth.uid() = id);

-- Driver Locations Policies
create policy "Allow public read of driver locations" on public.driver_locations
  for select using (true);

create policy "Allow drivers to update self location" on public.driver_locations
  for all using (auth.uid() = driver_id);

-- Rides Policies
create policy "Allow riders to view self rides" on public.rides
  for select using (auth.uid() = rider_id);

create policy "Allow drivers to view rides assigned to them or unassigned" on public.rides
  for select using (auth.uid() = driver_id or status = 'requested');

create policy "Allow riders to create rides" on public.rides
  for insert with check (auth.uid() = rider_id);

create policy "Allow updates of self rides" on public.rides
  for update using (auth.uid() = rider_id or auth.uid() = driver_id or status = 'requested');

-- Chats Policies
create policy "Allow participants to view chats" on public.chats
  for select using (
    exists (
      select 1 from public.rides r 
      where r.id = chats.ride_id 
      and (r.rider_id = auth.uid() or r.driver_id = auth.uid())
    )
  );

create policy "Allow participants to post chats" on public.chats
  for insert with check (
    sender_id = auth.uid() and 
    exists (
      select 1 from public.rides r 
      where r.id = chats.ride_id 
      and (r.rider_id = auth.uid() or r.driver_id = auth.uid())
    )
  );

-- Trust Circles Policies
create policy "Allow read of trust circles" on public.trust_circles
  for select using (true);

-- --------------------------------------------------
-- Realtime Setup
-- --------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;

alter publication supabase_realtime add table public.driver_locations;
alter publication supabase_realtime add table public.rides;
alter publication supabase_realtime add table public.chats;
