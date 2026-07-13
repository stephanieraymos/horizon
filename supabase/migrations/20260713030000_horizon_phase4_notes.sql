-- Horizon Phase 4: rich-text notes.
-- fam_trips gains notes_content jsonb (block document) — additive, Glade ignores.
-- New fam_travel_notes for reusable travel-knowledge notes ("never stop in
-- San Fernando"), block-document content + tags, family-scoped RLS.

alter table public.fam_trips add column if not exists notes_content jsonb;

create table if not exists public.fam_travel_notes (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null,
  title text not null default '',
  content jsonb not null default '[]'::jsonb,
  tags text[] not null default '{}',
  place_id uuid references public.fam_places(id) on delete set null,
  destination_id uuid references public.fam_destinations(id) on delete set null,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.fam_travel_notes enable row level security;

create policy fam_travel_notes_select on public.fam_travel_notes
  for select using (family_id = fam_current_family_id());

create policy fam_travel_notes_admin_write on public.fam_travel_notes
  for all using (family_id = fam_current_family_id() and fam_is_admin())
  with check (family_id = fam_current_family_id() and fam_is_admin());
