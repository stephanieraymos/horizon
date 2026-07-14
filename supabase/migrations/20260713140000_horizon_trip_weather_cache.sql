-- Cached daily forecast for a trip, so the weather strip doesn't re-fetch on
-- every view. Refreshed by the app when stale or when destination/dates change.
alter table public.fam_trips add column if not exists weather_cache jsonb;
