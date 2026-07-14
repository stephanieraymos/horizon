-- Per-photo tag for the Horizon trip mood board. Each mood-board photo is one
-- fam_memories row (single entry in photo_urls); `tag` labels it for filtering
-- by tag alongside uploader (added_by). Shared with TheGlade albums; nullable so
-- existing rows are unaffected.
alter table fam_memories add column if not exists tag text;
