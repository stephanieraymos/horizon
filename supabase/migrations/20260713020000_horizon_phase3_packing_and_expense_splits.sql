-- Horizon Phase 3: packing categories + per-person expense splitting.
-- All additive. fam_trip_packing.member_id stays required (Glade needs it);
-- fam_trip_expenses keeps amount/logged_* unchanged so Glade still decodes.

alter table public.fam_trip_packing
  add column if not exists category text;

alter table public.fam_trip_expenses
  add column if not exists paid_by uuid,
  add column if not exists spent_on date,
  add column if not exists place_id uuid references public.fam_places(id) on delete set null;

create table if not exists public.fam_expense_splits (
  id uuid primary key default gen_random_uuid(),
  expense_id uuid not null references public.fam_trip_expenses(id) on delete cascade,
  member_id uuid not null,
  amount numeric not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists idx_fam_expense_splits_expense
  on public.fam_expense_splits(expense_id);

alter table public.fam_expense_splits enable row level security;

create policy fam_expense_splits_select on public.fam_expense_splits
  for select using (
    exists (select 1 from public.fam_trip_expenses e
            join public.fam_trips t on t.id = e.trip_id
            where e.id = expense_id and t.family_id = fam_current_family_id()));

create policy fam_expense_splits_admin_write on public.fam_expense_splits
  for all using (
    exists (select 1 from public.fam_trip_expenses e
            join public.fam_trips t on t.id = e.trip_id
            where e.id = expense_id and t.family_id = fam_current_family_id() and fam_is_admin()))
  with check (
    exists (select 1 from public.fam_trip_expenses e
            join public.fam_trips t on t.id = e.trip_id
            where e.id = expense_id and t.family_id = fam_current_family_id() and fam_is_admin()));
