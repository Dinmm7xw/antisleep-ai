-- ========================================================
-- AntiSleep AI: Supabase PostgreSQL Database Schema
-- Run this in your Supabase Dashboard -> SQL Editor -> Run
-- ========================================================

-- 1. Drivers Profile Table
create table if not exists public.drivers (
  id uuid default gen_random_uuid() primary key,
  email_or_phone text unique not null,
  name text,
  car_plate text,
  language text default 'kk',
  sos_phone text,
  is_guest boolean default false,
  updated_at timestamp with time zone default timezone('utc'::text, now())
);

-- 2. Completed Trips History Table
create table if not exists public.trips (
  id uuid default gen_random_uuid() primary key,
  driver_identifier text not null,
  duration_seconds integer default 0,
  safety_score integer default 100,
  microsleep_count integer default 0,
  yawns_count integer default 0,
  blinks_count integer default 0,
  average_ear numeric(4,2) default 0.30,
  perclos_percent numeric(5,2) default 0.0,
  created_at timestamp with time zone default timezone('utc'::text, now())
);

-- 3. Real-Time Drowsiness & Sleep Incidents Log
create table if not exists public.incidents (
  id uuid default gen_random_uuid() primary key,
  driver_identifier text not null,
  event_type text not null, -- 'microsleep', 'yawn', 'head_nod'
  ear numeric(4,2),
  lat numeric(10,6),
  lng numeric(10,6),
  created_at timestamp with time zone default timezone('utc'::text, now())
);

-- Enable Row Level Security (RLS)
alter table public.drivers enable row level security;
alter table public.trips enable row level security;
alter table public.incidents enable row level security;

-- Allow Flutter client with anon publishable key to read and insert
create policy "Allow public read-write drivers" on public.drivers for all using (true) with check (true);
create policy "Allow public read-write trips" on public.trips for all using (true) with check (true);
create policy "Allow public read-write incidents" on public.incidents for all using (true) with check (true);

