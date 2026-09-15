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

## Countdowns: the plan is the countdown (2026-09-13)

`EventsStore.syncCountdown` writes a hidden `fam_events` copy for every dated plan
(linked, Vacation, not annual — `FamilyEvent.isPlanCopy`). Solstice's calendar reads
those rows, so they stay; Horizon never displays them — `CountdownBuilder` shows the
plan instead. A linked row that is NOT a copy is a countdown the plan was made from
("Plan a dinner" on the anniversary) and belongs to her:

- `syncCountdown` must never rewrite it (it used to — an annual anniversary became a
  one-off "Vacation ✈️").
- `deleteForTrip` deletes only the copy and unlinks the rest (it used to delete all).
- Unlinking needs an explicit JSON null (`TripLinkPatch`); a synthesized Encodable
  drops a nil optional and PostgREST gets an empty update that changes nothing.

## Seeing past sign-in on a simulator

Debug builds take `-HorizonDemo`: auth is skipped and `DemoMode.seed` fills the
stores; `TripsStore` / `EventsStore` / `FamilyStore` `load()` return early while it's
on, or the first refresh would wipe the sample data. Everything is `#if DEBUG`.
`xcrun simctl launch <udid> com.stephanieraymos.horizon -HorizonDemo`

## Nights vs days: `fam_trips.overnight` (2026-09-13)

A multi-day plan is either a stay (count nights) or something she goes to each day
and comes home from, like a festival (count days). `overnight` is nullable: NULL
means "the kind's default" (a trip stays over, events don't), so every existing row
kept showing exactly what it did. Show a plan's length only through
`Trip.lengthLabel` ("3 nights" / "4 days"), never `nights` directly. Aftershock is a
`trip` with `overnight = false`. `encode` always writes the key, so switching back
clears it; older builds that don't send it leave the column untouched on upsert.

## Cover banner: never layer a Button over a PhotosPicker

Reframe used to float over a full-banner `PhotosPicker`, and on her phone taps
on it opened the photo picker. The simulator did NOT reproduce this (the same
build's Reframe opened Adjust Cover), so don't trust a simulator pass on overlapping
hit targets. With a cover set, the photo is not a picker; Reframe (Button) and
Change (PhotosPicker) are separate pills with nothing under either one.
A helper `func` returning `some View` can't be called inside a `PhotosPicker`
label closure under Swift 6 (non-Sendable result into a nonisolated context).
Write the label inline.


## Adjust Cover previews at the BANNER's shape (2026-09-14)

`CoverCropView` used a fixed 240 pt preview while the trip banner is 170 pt tall.
Aspect-fill overflows on only ONE axis, and which one depends on the frame's shape,
so a photo that overflowed the banner top-to-bottom fit the preview exactly on that
axis: every vertical drag did nothing ("it won't let me drag"), and the only axis
that moved was one the banner never shows. `TripDetailView` now measures the banner
(`onGeometryChange`) and passes `bannerAspect`; overflow is recomputed each layout
from the loaded image size, not measured once in a `.task`. Any new surface that
reframes a photo must preview at the shape it will be shown at.

## Exact times: `fam_events.event_time`, `fam_trips.start_time` (2026-09-14)

Both are Postgres `time` (local wall clock, no zone), nullable, "HH:mm:ss" as a
String in Swift (`TimeOfDay`). NULL = all day = count to the start of the day, which
is every row from before this. `FamilyEvent.nextMoment` / `Trip.startMoment` combine
date + time via components, never `bySetting:`.

- `Trip.startTime` is decode-only; saved via `TripsStore.saveStartTime` — from the
  plan header's "Add a start time" AND from TripEditView's "Start time" toggle (which
  patches after the upsert, only when it changed) — so the plain trip upsert (which
  omits it) never clears it, and neither do EventActions' or Duplicate's saves.
- `EventsStore.upsert` ALWAYS writes `event_time` (custom `encode`), so turning the
  time off in the editor clears it. `saveTime` / `saveNote` / `saveCover` patch one
  column with an explicit JSON null. A synthesized Encodable drops a nil optional and
  PostgREST then changes nothing — `clearTripCover` had exactly this bug ("Remove
  cover photo" never removed it) until this commit.
- The note IS `fam_events.description` (the editor's old "Description" field).

## Countdown cards tick every second

`CountdownCard` / `PeriodCard` / `LiveCountdown` each run a 1 s `TimelineView`. Rows
are cards in a List (`cardRow()`: clear background, no separator, zero insets) with
the NavigationLink hidden behind the card — a link label draws a chevron. Countdown
cards keep ONE contextMenu + swipe (the measured-safe pairing). Countdown photos
live in `fam_events.cover_photo_url` as storage paths (`covers/event-…`); The Glade
decodes the column but draws nothing from it.
