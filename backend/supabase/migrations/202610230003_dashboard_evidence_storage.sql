insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'dashboard-evidence',
  'dashboard-evidence',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
on conflict (id) do update
set name = excluded.name,
    public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Admins read dashboard evidence" on storage.objects;
create policy "Admins read dashboard evidence"
  on storage.objects
  for select to authenticated
  using (
    bucket_id = 'dashboard-evidence'
    and public.is_admin()
  );

drop policy if exists "Admins upload dashboard evidence" on storage.objects;
create policy "Admins upload dashboard evidence"
  on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'dashboard-evidence'
    and public.is_admin()
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Admins delete dashboard evidence" on storage.objects;
create policy "Admins delete dashboard evidence"
  on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'dashboard-evidence'
    and public.is_admin()
  );
