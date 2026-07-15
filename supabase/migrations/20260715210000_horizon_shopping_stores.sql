-- Managed shopping "stores" (where to buy an item), mirroring the pattern of
-- fam_packing_categories. A store is family-scoped; the shopping "From" field
-- and the store filter both draw from this canonical list, and the quick-capture
-- parser matches spoken store names against it (case-insensitive).

create table if not exists public.fam_shopping_stores (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null,
  name text not null,
  created_at timestamptz not null default now()
);

-- One store per name per family (case-insensitive), so "Walmart"/"walmart"
-- collapse and createShoppingStore can rely on the DB to dedupe.
create unique index if not exists fam_shopping_stores_family_name_lower
  on public.fam_shopping_stores (family_id, lower(name));

alter table public.fam_shopping_stores enable row level security;

-- Shopping is collaborative — any family member can read and manage stores
-- (unlike packing categories, which are admin-gated).
create policy fam_shopping_stores_select on public.fam_shopping_stores
  for select using (family_id = fam_current_family_id());
create policy fam_shopping_stores_write on public.fam_shopping_stores
  for all using (family_id = fam_current_family_id())
  with check (family_id = fam_current_family_id());

-- Seed from stores already typed into existing shopping/expense items, so the
-- list isn't empty on first launch. Dedupe case-insensitively per family.
insert into public.fam_shopping_stores (family_id, name)
select family_id, name from (
  select distinct on (t.family_id, lower(btrim(e.purchased_from)))
         t.family_id as family_id,
         btrim(e.purchased_from) as name
  from public.fam_trip_expenses e
  join public.fam_trips t on t.id = e.trip_id
  where e.purchased_from is not null and btrim(e.purchased_from) <> ''
  order by t.family_id, lower(btrim(e.purchased_from))
) d
on conflict (family_id, lower(name)) do nothing;
