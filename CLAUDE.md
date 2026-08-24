# Horizon — trips

## Pending: adopt shared work-day tracking

`work_days` and `leave_allowances` (family Supabase `ihvljgwfslxorxsorzpi`) record
where each day was spent — `studio` / `home` / `day_off` / `weekend` — and, for a day
off, why (`vacation`, `sick`, `holiday`, `bereavement`, `jury_duty`, `unpaid`,
`parental`). One row per `(user_id, date)`, RLS-scoped to the owner, with `hours` (8 = a
full day) rather than a day count, so it matches the payroll system exactly. `hours` records
the time — 8 for a full day, 4 for a half — matching the payroll system.

The models, store and views already exist in **AppShellKit**: `WorkDaysStore`
(inject the app's `SupabaseClient`), `WorkDayPicker`, `LeaveBalancesCard`,
`LeaveProjectionsCard`, `WorkYearCalendar`. Spect writes these rows from its morning flow. Do not
re-implement any of it here.

What Horizon should do with it:
- Show remaining vacation when planning a trip — `WorkDaysStore.balances` gives
  allowance, taken and remaining per type for a year.
- Warn when a trip's working days would exceed what's left, before it's booked.
- On confirming a trip, offer to write its weekdays as `day_off` / `vacation` so the
  balance stays true without her marking each morning in Spect.

Note `LeaveType.countsAgainstAllowance`: holidays, winter break, bereavement and
jury duty are tracked but deliberately don't draw down a personal allowance.

Balances are **projected, not stored**. `leave_policies` holds the weekly accrual
rate, the cap and the weekday payroll posts on; `leave_anchors` holds a figure
read off the payroll system. `WorkDaysStore.projections` replays it week by week
— accrual pauses at the cap and resumes below it, and spending is applied before
accruing so a day taken mid-week frees room under the cap. Don't reimplement this
as `anchor + rate × weeks − used`; that overstates the balance near the cap.
