create or replace function public.reset_operational_data(p_payload jsonb)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  saved_updated_at timestamptz;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_payload) is distinct from 'object'
    or p_payload->'drains' is distinct from '[]'::jsonb
    or p_payload->'reports' is distinct from '[]'::jsonb
    or p_payload->'activities' is distinct from '[]'::jsonb
    or p_payload->'outcomes' is distinct from '[]'::jsonb
    or p_payload->'creditPools' is distinct from '[]'::jsonb
    or p_payload->'creditAllocations' is distinct from '[]'::jsonb
    or p_payload->'creditAudits' is distinct from '[]'::jsonb
    or jsonb_typeof(p_payload->'workers') is distinct from 'array'
    or jsonb_typeof(p_payload->'crews') is distinct from 'array'
    or jsonb_typeof(p_payload->'creditPolicy') is distinct from 'object'
  then
    raise exception 'Invalid operational reset payload'
      using errcode = '22023';
  end if;

  delete from public.credit_awards;
  delete from public.leave_requests;
  delete from public.field_tasks;
  delete from public.citizen_reports;

  insert into public.dashboard_state (id, payload, updated_by, updated_at)
  values ('municipal', p_payload, auth.uid(), clock_timestamp())
  on conflict (id) do update
    set payload = excluded.payload,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at
  returning updated_at into saved_updated_at;

  return saved_updated_at;
end;
$$;

revoke all on function public.reset_operational_data(jsonb)
  from public, anon;
grant execute on function public.reset_operational_data(jsonb)
  to authenticated;

drop policy if exists "Admins read citizen photos" on storage.objects;
create policy "Admins read citizen photos"
  on storage.objects
  for select to authenticated
  using (
    bucket_id = 'citizen-photos'
    and public.is_admin()
  );

drop policy if exists "Admins delete citizen photos" on storage.objects;
create policy "Admins delete citizen photos"
  on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'citizen-photos'
    and public.is_admin()
  );

drop policy if exists "Admins delete work photos" on storage.objects;
create policy "Admins delete work photos"
  on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'work-photos'
    and public.is_admin()
  );
