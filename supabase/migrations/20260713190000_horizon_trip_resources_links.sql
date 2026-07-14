-- "Resources" can be a file (storage_path) OR a link (url). Make storage_path
-- optional and add a url column so links don't need an upload.
alter table public.fam_trip_documents alter column storage_path drop not null;
alter table public.fam_trip_documents add column if not exists url text;
