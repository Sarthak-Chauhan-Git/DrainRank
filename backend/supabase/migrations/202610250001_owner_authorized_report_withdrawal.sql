create or replace function public.withdraw_citizen_report(p_report_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_uid uuid := auth.uid();
  current_status text;
begin
  if current_uid is null then
    raise exception 'Sign in to withdraw a report'
      using errcode = '42501';
  end if;

  select status
  into current_status
  from public.citizen_reports
  where report_id = p_report_id
    and reporter_id = current_uid
  for update;

  if not found then
    raise exception 'Report not found for this account'
      using errcode = '42501';
  end if;

  if current_status is null
    or current_status not in ('complaint_received', 'under_verification') then
    raise exception 'Reports can only be withdrawn before work is assigned'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.field_tasks
    where source_report_ids @> array[p_report_id]
  ) then
    raise exception 'This report already has assigned work'
      using errcode = '22023';
  end if;

  update public.citizen_reports
  set status = 'withdrawn'
  where report_id = p_report_id
    and reporter_id = current_uid;
end;
$$;

revoke all on function public.withdraw_citizen_report(text)
  from public, anon;
grant execute on function public.withdraw_citizen_report(text)
  to authenticated;
