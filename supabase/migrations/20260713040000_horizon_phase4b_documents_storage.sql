-- Horizon Phase 4b: document/attachment storage (booking confirmations, tickets,
-- passports). Private bucket, family-scoped by the first path segment
-- (<family_id>/<trip_id>/<uuid>.<ext>). New bucket + table — no Glade impact.

insert into storage.buckets (id, name, public)
values ('trip-docs', 'trip-docs', false)
on conflict (id) do nothing;

create policy "trip_docs_read" on storage.objects for select to authenticated
  using (bucket_id = 'trip-docs'
         and (storage.foldername(name))[1] = fam_current_family_id()::text);

create policy "trip_docs_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'trip-docs'
              and (storage.foldername(name))[1] = fam_current_family_id()::text);

create policy "trip_docs_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'trip-docs'
         and (storage.foldername(name))[1] = fam_current_family_id()::text);

create table if not exists public.fam_trip_documents (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null,
  trip_id uuid references public.fam_trips(id) on delete cascade,
  reservation_id uuid references public.fam_reservations(id) on delete set null,
  kind text not null default 'other',
  storage_path text not null,
  file_name text,
  content_type text,
  title text,
  notes text,
  is_sensitive boolean not null default false,
  created_by uuid,
  created_at timestamptz not null default now()
);

create index if not exists idx_fam_trip_documents_trip on public.fam_trip_documents(trip_id);

alter table public.fam_trip_documents enable row level security;

create policy fam_trip_documents_select on public.fam_trip_documents
  for select using (family_id = fam_current_family_id());

create policy fam_trip_documents_admin_write on public.fam_trip_documents
  for all using (family_id = fam_current_family_id() and fam_is_admin())
  with check (family_id = fam_current_family_id() and fam_is_admin());
