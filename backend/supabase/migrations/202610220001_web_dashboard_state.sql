create or replace function public.save_dashboard_state(
  p_payload jsonb,
  p_expected_updated_at timestamptz
)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  current_updated_at timestamptz;
  saved_updated_at timestamptz;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'Dashboard state must be a JSON object'
      using errcode = '22023';
  end if;

  select updated_at
  into current_updated_at
  from public.dashboard_state
  where id = 'municipal'
  for update;

  if not found then
    if p_expected_updated_at is not null then
      raise exception 'Dashboard state changed. Reload before saving.'
        using errcode = '40001';
    end if;
    insert into public.dashboard_state (id, payload, updated_by, updated_at)
    values ('municipal', p_payload, auth.uid(), clock_timestamp())
    returning updated_at into saved_updated_at;
    return saved_updated_at;
  end if;

  if p_expected_updated_at is null
    or current_updated_at is distinct from p_expected_updated_at then
    raise exception 'Dashboard state changed. Reload before saving.'
      using errcode = '40001';
  end if;

  update public.dashboard_state
  set payload = p_payload,
      updated_by = auth.uid(),
      updated_at = clock_timestamp()
  where id = 'municipal'
  returning updated_at into saved_updated_at;

  return saved_updated_at;
end;
$$;

revoke all on function public.save_dashboard_state(jsonb, timestamptz)
  from public, anon;
grant execute on function public.save_dashboard_state(jsonb, timestamptz)
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
    raise exception 'Report statuses must be an array' using errcode = '22023';
  end if;

  for status_item in select value from jsonb_array_elements(p_statuses)
  loop
    next_status := status_item->>'status';
    if next_status is null or next_status not in (
      'complaint_received', 'under_verification', 'work_assigned',
      'cleaning_completed', 'under_monitoring', 'duplicate', 'resolved'
    ) then
      raise exception 'Invalid citizen report status' using errcode = '22023';
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
