alter table public.fam_trip_purchases add column if not exists link text;

-- Tidy the imported item whose NAME was a raw Amazon URL: move it to the link.
update public.fam_trip_purchases
  set link = name, name = 'Amazon saved item'
  where family_id = 'a0960a58-4230-4a10-8658-a4a6a9a9bbc9'
    and name like 'http%';
