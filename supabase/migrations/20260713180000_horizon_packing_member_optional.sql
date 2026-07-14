-- A packing item no longer requires a person — null member_id means "Everyone".
-- Horizon owns trip packing now; TheGlade's trip feature is being retired.
alter table public.fam_trip_packing alter column member_id drop not null;
