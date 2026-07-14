-- Pre-trip checklist: tasks (with optional due dates) distinct from packing.
-- Family-writable so any adult can manage the list.
create table if not exists public.fam_trip_todos (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null,
  family_id uuid not null,
  title text not null,
  done boolean not null default false,
  due_date date,
  sort integer not null default 0,
  created_by uuid,
  created_at timestamptz not null default now()
);

create index if not exists fam_trip_todos_trip_idx on public.fam_trip_todos(trip_id);

alter table public.fam_trip_todos enable row level security;

create policy fam_trip_todos_select on public.fam_trip_todos
  for select using (family_id = fam_current_family_id());
create policy fam_trip_todos_write on public.fam_trip_todos
  for all using (family_id = fam_current_family_id())
  with check (family_id = fam_current_family_id());
