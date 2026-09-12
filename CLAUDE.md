# Horizon — trips

**This file is the repo-local layer: build commands and the traps already paid for
in this code. It is loaded automatically. It is NOT the project documentation.**

## Read these before you start, and write back to them as you finish

| Document | Path |
| :-- | :-- |
| Workstation brief — architecture, features, design rules | `Cowork OS/Projects/Horizon/CLAUDE.md` |
| Living status — current state, decisions, backlog | `Cowork OS/Projects/Horizon/MEMORY.md` |
| Plan — phases and rationale, where one exists | `Cowork OS/Projects/Horizon/plan.md` |

**Update MEMORY.md as each piece of work finishes, not at the end of the session.**
An interrupted session takes undocumented work with it, and the next one starts from
a status line that is already wrong. Write the entry the moment a feature lands or a
decision is made, keep `*Last updated:*` current, and correct the workstation
CLAUDE.md whenever it and the code disagree — the code is the truth, the doc is what
the next session reads.

`Cowork OS` = `~/Library/Mobile Documents/com~apple~CloudDocs/Cowork OS`.

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

## Split-view detail identity (2026-09-11)

`TripDetailView` owns a whole `TripDetailStore` plus edit/reservation/cover-photo
state seeded from the trip at init. Hosted in `EventsBoardView`'s split-view
detail column with no `.id()`, switching trips left the previous trip's entire
detail (and any in-flight edit) on screen under the newly selected trip. Fixed
with `.id(trip.id)` at the call site. `NotesTabView`'s equivalent split already
had this right (`.id(note.id)`, with its own comment) — match that pattern for
any new split-view detail screen. See `~/.claude/CLAUDE.md`'s "SwiftUI
conventions" section for the general shape of this trap.
