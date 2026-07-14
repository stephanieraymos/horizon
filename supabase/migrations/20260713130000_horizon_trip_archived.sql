-- "Not going" / archive flag for trips. Nullable-safe default; other apps that
-- read fam_trips simply ignore the unknown column on decode.
alter table public.fam_trips add column if not exists archived boolean not null default false;
