alter table public.citizen_reports enable row level security;

grant select, insert on public.citizen_reports to authenticated;

drop policy if exists "Citizens read own reports" on public.citizen_reports;
create policy "Citizens read own reports"
  on public.citizen_reports
  for select to authenticated
  using (
    (
      reporter_id = (select auth.uid())
      and (select public.current_profile_role()) = 'citizen'
    )
    or (select public.is_admin())
  );

drop policy if exists "Citizens submit own reports" on public.citizen_reports;
create policy "Citizens submit own reports"
  on public.citizen_reports
  for insert to authenticated
  with check (
    reporter_id = (select auth.uid())
    and (select public.current_profile_role()) = 'citizen'
  );

drop policy if exists "Citizens upload own report photos"
  on storage.objects;
create policy "Citizens upload own report photos"
  on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'citizen-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select public.current_profile_role()) = 'citizen'
  );

drop policy if exists "Citizens read own report photos"
  on storage.objects;
create policy "Citizens read own report photos"
  on storage.objects
  for select to authenticated
  using (
    bucket_id = 'citizen-photos'
    and (
      (
        (storage.foldername(name))[1] = (select auth.uid())::text
        and (select public.current_profile_role()) = 'citizen'
      )
      or (select public.is_admin())
    )
  );

drop policy if exists "Citizens delete own report photos"
  on storage.objects;
create policy "Citizens delete own report photos"
  on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'citizen-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select public.current_profile_role()) = 'citizen'
  );
