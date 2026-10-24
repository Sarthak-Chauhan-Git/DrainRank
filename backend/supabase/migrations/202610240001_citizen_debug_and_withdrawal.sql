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
  if current_uid is null
    or (select public.current_profile_role()) is distinct from 'citizen' then
    raise exception 'Citizen access is required to withdraw a report'
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

create or replace function public.update_citizen_report_statuses(
  p_statuses jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  status_item jsonb;
  next_status text;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_statuses) is distinct from 'array' then
    raise exception 'Report statuses must be an array'
      using errcode = '22023';
  end if;

  for status_item in select value from jsonb_array_elements(p_statuses)
  loop
    next_status := status_item->>'status';
    if next_status is null or next_status not in (
      'complaint_received', 'under_verification', 'work_assigned',
      'cleaning_completed', 'under_monitoring', 'duplicate', 'resolved',
      'withdrawn'
    ) then
      raise exception 'Invalid citizen report status'
        using errcode = '22023';
    end if;
    if nullif(status_item->>'report_id', '') is null then
      raise exception 'Report status entry must include a report id'
        using errcode = '22023';
    end if;
    update public.citizen_reports
    set status = next_status
    where report_id = status_item->>'report_id';
  end loop;
end;
$$;

revoke all on function public.update_citizen_report_statuses(jsonb)
  from public, anon;
grant execute on function public.update_citizen_report_statuses(jsonb)
  to authenticated;

create or replace function public.debug_delete_citizen_reports(
  p_report_ids text[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_uid uuid := auth.uid();
  report_row record;
  deleted_report_ids text[] := '{}';
  image_paths text[] := '{}';
  skipped_assigned_count integer := 0;
begin
  if current_uid is null
    or (select public.current_profile_role()) is distinct from 'citizen' then
    raise exception 'Citizen access is required to manage test reports'
      using errcode = '42501';
  end if;

  for report_row in
    select report_id, image_path
    from public.citizen_reports
    where reporter_id = current_uid
      and status in (
        'complaint_received',
        'under_verification',
        'withdrawn'
      )
      and (p_report_ids is null or report_id = any(p_report_ids))
    for update
  loop
    if exists (
      select 1
      from public.field_tasks
      where source_report_ids @> array[report_row.report_id]
    ) then
      skipped_assigned_count := skipped_assigned_count + 1;
      continue;
    end if;

    delete from public.citizen_reports
    where report_id = report_row.report_id
      and reporter_id = current_uid;

    if found then
      deleted_report_ids := array_append(
        deleted_report_ids,
        report_row.report_id
      );
      if report_row.image_path is not null
        and report_row.image_path <> '' then
        image_paths := array_append(image_paths, report_row.image_path);
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'deleted_report_ids', deleted_report_ids,
    'image_paths', image_paths,
    'skipped_assigned_count', skipped_assigned_count
  );
end;
$$;

revoke all on function public.debug_delete_citizen_reports(text[])
  from public, anon;
grant execute on function public.debug_delete_citizen_reports(text[])
  to authenticated;

drop policy if exists "Citizens delete own report photos"
  on storage.objects;
create policy "Citizens delete own report photos"
  on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'citizen-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
