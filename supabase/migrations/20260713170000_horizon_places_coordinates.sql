-- Exact coordinates captured from the map search, so weather/maps don't need to
-- re-geocode a messy string.
alter table public.fam_places add column if not exists latitude double precision;
alter table public.fam_places add column if not exists longitude double precision;
-- Optional location for a destination grouping, so any trip using that
-- destination knows where it is.
alter table public.fam_destinations add column if not exists place_id uuid;
alter table public.fam_destinations add column if not exists latitude double precision;
alter table public.fam_destinations add column if not exists longitude double precision;
