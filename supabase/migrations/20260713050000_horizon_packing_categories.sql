create table if not exists public.fam_packing_categories (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null,
  name text not null,
  icon text not null default 'shippingbox',
  sort integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.fam_packing_categories enable row level security;

create policy fam_packing_categories_select on public.fam_packing_categories
  for select using (family_id = fam_current_family_id());
create policy fam_packing_categories_admin_write on public.fam_packing_categories
  for all using (family_id = fam_current_family_id() and fam_is_admin())
  with check (family_id = fam_current_family_id() and fam_is_admin());

-- Default categories seeded per family (icons are editable in-app).
insert into public.fam_packing_categories (family_id, name, icon, sort) values
  ('a0960a58-4230-4a10-8658-a4a6a9a9bbc9', 'Clothes', 'tshirt', 0),
  ('a0960a58-4230-4a10-8658-a4a6a9a9bbc9', 'Bathroom', 'shower', 1),
  ('a0960a58-4230-4a10-8658-a4a6a9a9bbc9', 'Tech', 'laptopcomputer', 2),
  ('a0960a58-4230-4a10-8658-a4a6a9a9bbc9', 'Documents', 'doc.text', 3),
  ('a0960a58-4230-4a10-8658-a4a6a9a9bbc9', 'Snacks', 'takeoutbag.and.cup.and.straw', 4),
  ('a0960a58-4230-4a10-8658-a4a6a9a9bbc9', 'Kids', 'figure.and.child.holdinghands', 5),
  ('a0960a58-4230-4a10-8658-a4a6a9a9bbc9', 'Gear', 'backpack', 6),
  ('a0960a58-4230-4a10-8658-a4a6a9a9bbc9', 'Other', 'shippingbox', 7);
