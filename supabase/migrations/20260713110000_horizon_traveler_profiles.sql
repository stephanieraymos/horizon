-- Reusable per-member travel documents: passport, Known Traveler/TSA, loyalty
-- programs. Sensitive PII, kept behind family-scoped RLS. One row per member.
create table if not exists public.fam_traveler_profiles (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null,
  member_id uuid not null unique,
  passport_number text,
  passport_expiry date,
  known_traveler_number text,
  loyalty_programs jsonb not null default '[]'::jsonb,
  notes text,
  updated_at timestamptz not null default now()
);

alter table public.fam_traveler_profiles enable row level security;

create policy fam_traveler_profiles_select on public.fam_traveler_profiles
  for select using (family_id = fam_current_family_id());
create policy fam_traveler_profiles_write on public.fam_traveler_profiles
  for all using (family_id = fam_current_family_id())
  with check (family_id = fam_current_family_id());
