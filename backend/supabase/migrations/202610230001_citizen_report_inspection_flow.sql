alter table public.field_tasks
  add column if not exists inspection_outcome text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'field_tasks_inspection_outcome_check'
      and conrelid = 'public.field_tasks'::regclass
  ) then
    alter table public.field_tasks
      add constraint field_tasks_inspection_outcome_check
      check (
        inspection_outcome is null
        or inspection_outcome in (
          'cleaning_required',
          'no_cleaning_required'
        )
      );
  end if;
end;
$$;

create or replace function public.clear_requeued_inspection_outcome()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.title ilike 'Inspect %'
    and (
      (old.status = 'Completed' and new.status = 'Pending')
      or old.title not ilike 'Inspect %'
    ) then
    new.status := 'Pending';
    new.inspection_outcome := null;
  end if;
  return new;
end;
$$;

revoke all on function public.clear_requeued_inspection_outcome()
  from public, anon, authenticated;

drop trigger if exists clear_requeued_inspection_outcome
  on public.field_tasks;
create trigger clear_requeued_inspection_outcome
before update on public.field_tasks
for each row
execute function public.clear_requeued_inspection_outcome();

drop function if exists public.submit_field_work_update(
  text, text, text, timestamptz, double precision, double precision,
  double precision, text
);
drop function if exists public.submit_field_work_update(
  text, text, text, timestamptz, double precision, double precision,
  double precision, text, text
);

create function public.submit_field_work_update(
  p_task_id text,
  p_description text,
  p_photo_path text,
  p_captured_at timestamptz,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_address text,
  p_inspection_outcome text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_uid uuid := auth.uid();
  task_row public.field_tasks%rowtype;
  update_id uuid;
  overdue boolean;
  is_inspection boolean;
begin
  if current_uid is null
    or (select public.current_profile_role()) is distinct from 'crew' then
    raise exception 'Active crew access required' using errcode = '42501';
  end if;
  if p_description is null or length(trim(p_description)) = 0 then
    raise exception 'Work description is required' using errcode = '22023';
  end if;
  if p_photo_path is null
    or p_photo_path !~ ('^' || current_uid::text || '/[^/]+/[^/]+$')
    or (storage.foldername(p_photo_path))[2] is distinct from p_task_id then
    raise exception 'Invalid work photo path' using errcode = '22023';
  end if;
  if p_latitude is null or p_longitude is null
    or p_latitude not between -90 and 90
    or p_longitude not between -180 and 180 then
    raise exception 'Invalid photo coordinates' using errcode = '22023';
  end if;
  if p_inspection_outcome is not null
    and p_inspection_outcome not in (
      'cleaning_required',
      'no_cleaning_required'
    ) then
    raise exception 'Invalid inspection outcome' using errcode = '22023';
  end if;

  select * into task_row
  from public.field_tasks
  where id = p_task_id
  for update;

  if not found or not (current_uid = any(task_row.assigned_to_uid)) then
    raise exception 'You are no longer assigned to this task'
      using errcode = '42501';
  end if;
  if task_row.date_key > current_date then
    raise exception 'Future tasks cannot be updated yet' using errcode = '22023';
  end if;

  is_inspection := task_row.title ilike 'Inspect %';
  if is_inspection and p_inspection_outcome is null then
    raise exception 'Select whether cleaning is required after inspection'
      using errcode = '22023';
  end if;
  if not is_inspection and p_inspection_outcome is not null then
    raise exception 'An inspection outcome can only be submitted for inspection tasks'
      using errcode = '22023';
  end if;
  if is_inspection and task_row.status = 'Completed'
    and task_row.inspection_outcome is not null then
    raise exception 'This inspection has already been submitted'
      using errcode = '22023';
  end if;

  if task_row.date_key < current_date and exists (
    select 1 from public.field_work_updates
    where task_id = p_task_id and submitted_by_uid = current_uid
  ) then
    raise exception 'Past task evidence cannot be edited' using errcode = '22023';
  end if;

  overdue := task_row.date_key < current_date;
  insert into public.field_work_updates (
    task_id, submitted_by_uid, description, photo_path, captured_at,
    submitted_overdue, latitude, longitude, accuracy_meters, address
  )
  values (
    p_task_id, current_uid, trim(p_description), p_photo_path, p_captured_at,
    overdue, p_latitude, p_longitude, p_accuracy_meters, p_address
  )
  on conflict (task_id, submitted_by_uid) do update
    set description = excluded.description,
        photo_path = excluded.photo_path,
        captured_at = excluded.captured_at,
        submitted_overdue = excluded.submitted_overdue,
        latitude = excluded.latitude,
        longitude = excluded.longitude,
        accuracy_meters = excluded.accuracy_meters,
        address = excluded.address,
        edited_at = now()
  returning id into update_id;

  update public.field_tasks
  set status = case
        when is_inspection then 'Completed'
        when status = 'Pending' then 'In Progress'
        else status
      end,
      inspection_outcome = coalesce(p_inspection_outcome, inspection_outcome),
      updated_at = now()
  where id = p_task_id;
  return update_id;
end;
$$;

revoke all on function public.submit_field_work_update(
  text, text, text, timestamptz, double precision, double precision,
  double precision, text, text
) from public, anon;
grant execute on function public.submit_field_work_update(
  text, text, text, timestamptz, double precision, double precision,
  double precision, text, text
) to authenticated;

create function public.submit_field_work_update(
  p_task_id text,
  p_description text,
  p_photo_path text,
  p_captured_at timestamptz,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_address text
)
returns uuid
language sql
security definer
set search_path = public
as $$
  select public.submit_field_work_update(
    p_task_id,
    p_description,
    p_photo_path,
    p_captured_at,
    p_latitude,
    p_longitude,
    p_accuracy_meters,
    p_address,
    null
  );
$$;

revoke all on function public.submit_field_work_update(
  text, text, text, timestamptz, double precision, double precision,
  double precision, text
) from public, anon;
grant execute on function public.submit_field_work_update(
  text, text, text, timestamptz, double precision, double precision,
  double precision, text
) to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'citizen_reports'
  ) then
    alter publication supabase_realtime
      add table public.citizen_reports;
  end if;
end;
$$;
