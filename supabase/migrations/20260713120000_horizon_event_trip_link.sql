-- Link a Countdown (fam_events) to a Trip. Nullable; TheGlade ignores the extra
-- column on decode, and its upserts omit it (so the link survives Glade edits).
alter table public.fam_events add column if not exists trip_id uuid;
create index if not exists fam_events_trip_idx on public.fam_events(trip_id);
