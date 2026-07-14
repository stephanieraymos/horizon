-- Multiple places per trip. Places live in fam_places (name + category +
-- address + maps_url from a map search); this joins them to a trip, ordered.
create table if not exists public.fam_trip_places (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null,
  place_id uuid not null references public.fam_places(id) on delete cascade,
  family_id uuid not null,
  sort integer not null default 0,
  created_at timestamptz not null default now(),
  unique (trip_id, place_id)
);

create index if not exists fam_trip_places_trip_idx on public.fam_trip_places(trip_id);

alter table public.fam_trip_places enable row level security;

create policy fam_trip_places_select on public.fam_trip_places
  for select using (family_id = fam_current_family_id());
create policy fam_trip_places_write on public.fam_trip_places
  for all using (family_id = fam_current_family_id())
  with check (family_id = fam_current_family_id());
