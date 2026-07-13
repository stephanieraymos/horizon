-- Horizon Phase 1: link trips to destinations, and turn destinations into the
-- wishlist / bucket-list unit. All columns are ADDITIVE and NULLABLE (or have
-- defaults) so TheGlade — which still decodes these tables until it's cut over —
-- keeps decoding existing rows unchanged. No status values or column types are
-- changed, so no existing decoder breaks.

alter table public.fam_trips
  add column if not exists destination_id uuid
    references public.fam_destinations(id) on delete set null;

alter table public.fam_destinations
  add column if not exists is_wishlist boolean not null default false,
  add column if not exists kind text,
  add column if not exists place_id uuid
    references public.fam_places(id) on delete set null,
  add column if not exists cover_photo_url text;

create index if not exists idx_fam_trips_destination_id
  on public.fam_trips(destination_id);
create index if not exists idx_fam_destinations_family_id
  on public.fam_destinations(family_id);
