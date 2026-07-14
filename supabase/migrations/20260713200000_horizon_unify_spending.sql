-- Unify shopping + expenses into fam_trip_expenses. A spending item has a status
-- (not_purchased / in_cart / purchased); purchased items are expenses that count
-- toward the budget and settle-up. Existing expenses default to 'purchased'.
alter table public.fam_trip_expenses add column if not exists status text not null default 'purchased';
alter table public.fam_trip_expenses add column if not exists tag text;
alter table public.fam_trip_expenses add column if not exists link text;
alter table public.fam_trip_expenses add column if not exists purchased_from text;
alter table public.fam_trip_expenses add column if not exists notes text;

insert into public.fam_trip_expenses
  (trip_id, category, description, amount, status, tag, link, purchased_from, notes, spent_on, paid_by)
select p.trip_id, 'Merch', p.name, coalesce(p.amount_cents, 0) / 100.0, p.status,
       p.tag, p.link, p.purchased_from, p.notes, p.purchase_date,
       case when p.status = 'purchased'
            then '77038cca-4ae9-4e0a-a4b2-97d1c5a2c9eb'::uuid else null end
from public.fam_trip_purchases p;
