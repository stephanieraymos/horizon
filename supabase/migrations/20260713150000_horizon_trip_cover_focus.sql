-- Focal point (0..1) for framing the cover photo in the banner. Default center.
alter table public.fam_trips add column if not exists cover_focus_x double precision not null default 0.5;
alter table public.fam_trips add column if not exists cover_focus_y double precision not null default 0.5;
