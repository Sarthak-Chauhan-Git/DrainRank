alter table public.citizen_reports enable row level security;
grant insert on public.citizen_reports to authenticated;

drop policy if exists "Citizens submit own reports"
  on public.citizen_reports;
create policy "Citizens submit own reports"
  on public.citizen_reports
  for insert to authenticated
  with check (reporter_id = (select auth.uid()));

drop policy if exists "Citizens upload own report photos"
  on storage.objects;
create policy "Citizens upload own report photos"
  on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'citizen-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

alter table public.field_work_updates
  add column if not exists cleaning_outcome text,
  add column if not exists review_status text not null default 'pending',
  add column if not exists reviewed_by uuid references auth.users(id),
  add column if not exists reviewed_at timestamptz,
  add column if not exists review_note text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'field_work_updates_cleaning_outcome_check'
      and conrelid = 'public.field_work_updates'::regclass
  ) then
    alter table public.field_work_updates
      add constraint field_work_updates_cleaning_outcome_check
      check (
        cleaning_outcome is null
        or cleaning_outcome in (
          'cleaned',
          'partially_cleaned',
          'unable_to_complete'
        )
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'field_work_updates_review_status_check'
      and conrelid = 'public.field_work_updates'::regclass
  ) then
    alter table public.field_work_updates
      add constraint field_work_updates_review_status_check
      check (
        review_status in (
          'pending',
          'accepted',
          'rework_requested',
          'location_mismatch'
        )
      );
  end if;
end;
$$;

drop function if exists public.submit_field_work_update(
  text, text, text, timestamptz, double precision, double precision,
  double precision, text
);
drop function if exists public.submit_field_work_update(
  text, text, text, timestamptz, double precision, double precision,
  double precision, text, text
);

create or replace function public.submit_field_work_update(
  p_task_id text,
  p_description text,
  p_photo_path text,
  p_captured_at timestamptz,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_address text,
  p_inspection_outcome text,
  p_cleaning_outcome text
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
  existing_review_status text;
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
  if p_cleaning_outcome is not null
    and p_cleaning_outcome not in (
      'cleaned',
      'partially_cleaned',
      'unable_to_complete'
    ) then
    raise exception 'Invalid cleaning outcome' using errcode = '22023';
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
  if is_inspection and p_cleaning_outcome is not null then
    raise exception 'A cleaning outcome cannot be submitted for an inspection task'
      using errcode = '22023';
  end if;
  if not is_inspection and p_cleaning_outcome is null then
    raise exception 'Select the cleaning result before submitting work evidence'
      using errcode = '22023';
  end if;
  if is_inspection and task_row.status = 'Completed'
    and task_row.inspection_outcome is not null then
    raise exception 'This inspection has already been submitted'
      using errcode = '22023';
  end if;

  select review_status into existing_review_status
  from public.field_work_updates
  where task_id = p_task_id and submitted_by_uid = current_uid
  for update;
  if existing_review_status = 'accepted' then
    raise exception 'Accepted evidence cannot be changed'
      using errcode = '22023';
  end if;
  if task_row.date_key < current_date
    and existing_review_status is not null
    and existing_review_status <> 'rework_requested' then
    raise exception 'Past task evidence cannot be edited'
      using errcode = '22023';
  end if;

  overdue := task_row.date_key < current_date;
  insert into public.field_work_updates (
    task_id, submitted_by_uid, description, photo_path, captured_at,
    submitted_overdue, latitude, longitude, accuracy_meters, address,
    cleaning_outcome, review_status, reviewed_by, reviewed_at, review_note
  )
  values (
    p_task_id, current_uid, trim(p_description), p_photo_path, p_captured_at,
    overdue, p_latitude, p_longitude, p_accuracy_meters, p_address,
    p_cleaning_outcome, 'pending', null, null, null
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
        cleaning_outcome = excluded.cleaning_outcome,
        review_status = 'pending',
        reviewed_by = null,
        reviewed_at = null,
        review_note = null,
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
  double precision, text, text, text
) from public, anon;
grant execute on function public.submit_field_work_update(
  text, text, text, timestamptz, double precision, double precision,
  double precision, text, text, text
) to authenticated;

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
    p_inspection_outcome,
    null
  );
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
    null,
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

create or replace function public.review_field_work_update(
  p_update_id uuid,
  p_decision text,
  p_review_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  evidence public.field_work_updates%rowtype;
  next_status text;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;

  next_status := case p_decision
    when 'accept' then 'accepted'
    when 'request_rework' then 'rework_requested'
    when 'flag_location_mismatch' then 'location_mismatch'
    else null
  end;
  if next_status is null then
    raise exception 'Invalid evidence review decision' using errcode = '22023';
  end if;

  select * into evidence
  from public.field_work_updates
  where id = p_update_id
  for update;
  if not found then
    raise exception 'Field evidence not found' using errcode = 'P0002';
  end if;
  if evidence.review_status <> 'pending' then
    raise exception 'This evidence has already been reviewed'
      using errcode = '22023';
  end if;

  update public.field_work_updates
  set review_status = next_status,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      review_note = nullif(trim(p_review_note), '')
  where id = p_update_id;

  update public.field_tasks
  set status = case
        when p_decision = 'accept'
          and not exists (
            select 1
            from unnest(assigned_to_uid) as assigned_member(uid)
            where not exists (
              select 1
              from public.field_work_updates as submitted
              where submitted.task_id = evidence.task_id
                and submitted.submitted_by_uid = assigned_member.uid
                and submitted.review_status = 'accepted'
            )
          )
          then 'Completed'
        else 'In Progress'
      end,
      updated_at = now()
  where id = evidence.task_id;
end;
$$;

revoke all on function public.review_field_work_update(uuid, text, text)
  from public, anon;
grant execute on function public.review_field_work_update(uuid, text, text)
  to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'field_work_updates'
  ) then
    alter publication supabase_realtime
      add table public.field_work_updates;
  end if;
end;
$$;

notify pgrst, 'reload schema';
