-- Horizon Phase 2: a single typed reservations table (TripIt-style) that
-- subsumes flights + lodging + car/rail/dining/activity/etc. New table, so no
-- existing decoder is affected. RLS mirrors fam_trips (select = family,
-- write = family + admin) via the parent trip.

create table if not exists public.fam_reservations (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null,
  trip_id uuid not null references public.fam_trips(id) on delete cascade,
  type text not null default 'other',
  title text not null,
  confirmation_number text,
  start_at timestamptz,
  end_at timestamptz,
  address text,
  maps_url text,
  place_id uuid references public.fam_places(id) on delete set null,
  cost_cents integer,
  details jsonb not null default '{}'::jsonb,
  notes text,
  sort integer not null default 0,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_fam_reservations_trip on public.fam_reservations(trip_id);

alter table public.fam_reservations enable row level security;

create policy fam_reservations_select on public.fam_reservations
  for select using (
    exists (select 1 from public.fam_trips t
            where t.id = trip_id and t.family_id = fam_current_family_id()));

create policy fam_reservations_admin_write on public.fam_reservations
  for all using (
    exists (select 1 from public.fam_trips t
            where t.id = trip_id and t.family_id = fam_current_family_id() and fam_is_admin()))
  with check (
    exists (select 1 from public.fam_trips t
            where t.id = trip_id and t.family_id = fam_current_family_id() and fam_is_admin()));
