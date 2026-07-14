-- Reusable packing templates (Beach, Disneyland, Camping, Ski + custom). A
-- template is a family-level named list of items; applying it to a trip copies
-- the items into fam_trip_packing for the chosen traveler(s). Items carry a free
-- text category (matched to fam_packing_categories for its icon), no member.
create table if not exists public.fam_packing_templates (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null,
  name text not null,
  icon text not null default 'suitcase',
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.fam_packing_template_items (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.fam_packing_templates(id) on delete cascade,
  item text not null,
  category text,
  sort integer not null default 0
);

create index if not exists fam_packing_template_items_template_idx
  on public.fam_packing_template_items(template_id);

alter table public.fam_packing_templates enable row level security;
alter table public.fam_packing_template_items enable row level security;

create policy fam_packing_templates_select on public.fam_packing_templates
  for select using (family_id = fam_current_family_id());
create policy fam_packing_templates_admin_write on public.fam_packing_templates
  for all using (family_id = fam_current_family_id() and fam_is_admin())
  with check (family_id = fam_current_family_id() and fam_is_admin());

create policy fam_packing_template_items_select on public.fam_packing_template_items
  for select using (exists (
    select 1 from public.fam_packing_templates t
    where t.id = template_id and t.family_id = fam_current_family_id()));
create policy fam_packing_template_items_admin_write on public.fam_packing_template_items
  for all using (exists (
    select 1 from public.fam_packing_templates t
    where t.id = template_id and t.family_id = fam_current_family_id() and fam_is_admin()))
  with check (exists (
    select 1 from public.fam_packing_templates t
    where t.id = template_id and t.family_id = fam_current_family_id() and fam_is_admin()));

-- Seed starter templates for the Raymos family (editable/removable in-app).
with t as (
  insert into public.fam_packing_templates (family_id, name, icon) values
    ('a0960a58-4230-4a10-8658-a4a6a9a9bbc9', 'Beach',      'beach.umbrella'),
    ('a0960a58-4230-4a10-8658-a4a6a9a9bbc9', 'Disneyland', 'sparkles'),
    ('a0960a58-4230-4a10-8658-a4a6a9a9bbc9', 'Camping',    'tent'),
    ('a0960a58-4230-4a10-8658-a4a6a9a9bbc9', 'Ski',        'snowflake')
  returning id, name
)
insert into public.fam_packing_template_items (template_id, item, category, sort)
select t.id, x.item, x.category, x.sort
from t
join (values
  ('Beach','Swimsuits','Clothes',0),
  ('Beach','Sunscreen','Bathroom',1),
  ('Beach','Beach towels','Gear',2),
  ('Beach','Sunglasses','Clothes',3),
  ('Beach','Flip flops','Clothes',4),
  ('Beach','Beach toys','Kids',5),
  ('Beach','Cooler','Gear',6),
  ('Beach','Sun hats','Clothes',7),
  ('Beach','Aloe vera','Bathroom',8),
  ('Beach','Water bottles','Gear',9),
  ('Disneyland','Park tickets','Documents',0),
  ('Disneyland','Comfortable shoes','Clothes',1),
  ('Disneyland','Portable charger','Tech',2),
  ('Disneyland','Sunscreen','Bathroom',3),
  ('Disneyland','Rain ponchos','Gear',4),
  ('Disneyland','Autograph book','Kids',5),
  ('Disneyland','Snacks','Snacks',6),
  ('Disneyland','Refillable water bottle','Gear',7),
  ('Disneyland','Hats','Clothes',8),
  ('Disneyland','Stroller','Kids',9),
  ('Camping','Tent','Gear',0),
  ('Camping','Sleeping bags','Gear',1),
  ('Camping','Camp stove','Gear',2),
  ('Camping','Flashlights','Gear',3),
  ('Camping','Bug spray','Bathroom',4),
  ('Camping','Firewood','Gear',5),
  ('Camping','Cooler','Gear',6),
  ('Camping','First aid kit','Gear',7),
  ('Camping','Camp chairs','Gear',8),
  ('Camping','Marshmallows','Snacks',9),
  ('Ski','Ski jacket','Clothes',0),
  ('Ski','Snow pants','Clothes',1),
  ('Ski','Gloves','Clothes',2),
  ('Ski','Goggles','Gear',3),
  ('Ski','Helmet','Gear',4),
  ('Ski','Base layers','Clothes',5),
  ('Ski','Hand warmers','Gear',6),
  ('Ski','Lip balm','Bathroom',7),
  ('Ski','Beanie','Clothes',8),
  ('Ski','Wool socks','Clothes',9)
) as x(name, item, category, sort) on x.name = t.name;
