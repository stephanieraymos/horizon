-- Swift's UUID.uuidString is uppercase but uuid::text is lowercase, so the
-- family-id path segment never matched and uploads were silently denied.
-- Compare case-insensitively.
drop policy if exists "trip_docs_read" on storage.objects;
drop policy if exists "trip_docs_insert" on storage.objects;
drop policy if exists "trip_docs_delete" on storage.objects;

create policy "trip_docs_read" on storage.objects for select to authenticated
  using (bucket_id = 'trip-docs'
         and lower((storage.foldername(name))[1]) = fam_current_family_id()::text);

create policy "trip_docs_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'trip-docs'
              and lower((storage.foldername(name))[1]) = fam_current_family_id()::text);

create policy "trip_docs_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'trip-docs'
         and lower((storage.foldername(name))[1]) = fam_current_family_id()::text);
