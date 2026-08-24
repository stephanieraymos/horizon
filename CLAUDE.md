# Horizon — trips

## Pending: adopt shared work-day tracking

`work_days` and `leave_allowances` (family Supabase `ihvljgwfslxorxsorzpi`) record
where each day was spent — `studio` / `home` / `day_off` / `weekend` — and, for a day
off, why (`vacation`, `sick`, `holiday`, `bereavement`, `jury_duty`, `unpaid`,
`parental`). One row per `(user_id, date)`, RLS-scoped to the owner. `amount` is 1.0
for a full day and 0.5 for a half day, so balances can legitimately read 12.5.

The models, store and views already exist in **AppShellKit**: `WorkDaysStore`
(inject the app's `SupabaseClient`), `WorkDayPicker`, `LeaveBalancesCard`,
`WorkYearCalendar`. Spect writes these rows from its morning flow. Do not
re-implement any of it here.

What Horizon should do with it:
- Show remaining vacation when planning a trip — `WorkDaysStore.balances` gives
  allowance, taken and remaining per type for a year.
- Warn when a trip's working days would exceed what's left, before it's booked.
- On confirming a trip, offer to write its weekdays as `day_off` / `vacation` so the
  balance stays true without her marking each morning in Spect.

Note `LeaveType.countsAgainstAllowance`: holidays, bereavement and jury duty are
tracked but deliberately don't draw down a personal allowance.
