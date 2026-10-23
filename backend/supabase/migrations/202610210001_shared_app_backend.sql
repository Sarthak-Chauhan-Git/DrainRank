alter table public.citizen_reports
  add column if not exists image_path text;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'leave_requests'
      and column_name = 'id'
      and column_default is null
  ) then
    alter table public.leave_requests
      alter column id set default gen_random_uuid();
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'leave_requests'
      and column_name = 'created_at'
      and column_default is null
  ) then
    alter table public.leave_requests
      alter column created_at set default now();
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'credit_awards'
      and column_name = 'created_at'
      and column_default is null
  ) then
    alter table public.credit_awards
      alter column created_at set default now();
  end if;
end;
$$;

create table if not exists public.field_tasks (
  id text primary key,
  title text not null,
  date_key date not null,
  start_time text,
  end_time text,
  location text,
  description text,
  status text not null default 'Pending',
  assigned_to_uid uuid[] not null default '{}',
  crew_members jsonb not null default '[]'::jsonb,
  work_window_start timestamptz not null,
  work_window_end timestamptz not null,
  daily_overdue_deduction integer not null default 0
    check (daily_overdue_deduction >= 0),
  source_report_ids text[] not null default '{}',
  source_work_order_id text,
  updated_at timestamptz not null default now()
);

create index if not exists field_tasks_assigned_uid_idx
  on public.field_tasks using gin (assigned_to_uid);
create index if not exists field_tasks_date_idx
  on public.field_tasks (date_key);

alter table public.field_tasks enable row level security;
revoke all on public.field_tasks from anon, authenticated;
grant select on public.field_tasks to authenticated;

drop policy if exists "Crew read assigned field tasks"
  on public.field_tasks;
create policy "Crew read assigned field tasks"
  on public.field_tasks
  for select to authenticated
  using (
    public.is_admin()
    or (
      (select auth.uid()) = any (assigned_to_uid)
      and (select public.current_profile_role()) = 'crew'
    )
  );

create table if not exists public.field_work_updates (
  id uuid primary key default gen_random_uuid(),
  task_id text not null references public.field_tasks (id) on delete cascade,
  submitted_by_uid uuid not null references public.profiles (id) on delete cascade,
  description text not null,
  photo_path text not null,
  captured_at timestamptz not null,
  submitted_at timestamptz not null default now(),
  edited_at timestamptz,
  submitted_overdue boolean not null default false,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  accuracy_meters double precision
    check (accuracy_meters is null or accuracy_meters >= 0),
  address text,
  unique (task_id, submitted_by_uid)
);

create index if not exists field_work_updates_task_idx
  on public.field_work_updates (task_id, submitted_at desc);

alter table public.field_work_updates enable row level security;
revoke all on public.field_work_updates from anon, authenticated;
grant select on public.field_work_updates to authenticated;

drop policy if exists "Crew and admins read field work updates"
  on public.field_work_updates;
create policy "Crew and admins read field work updates"
  on public.field_work_updates
  for select to authenticated
  using (
    public.is_admin()
    or (
      submitted_by_uid = (select auth.uid())
      and (select public.current_profile_role()) = 'crew'
    )
  );

create or replace function public.sync_dashboard_field_tasks(p_tasks jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  task_item jsonb;
  task_date date;
  assignee_ids text[];
  task_assignees uuid[];
  crew_list jsonb;
  task_status text;
  task_id text;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_tasks) is distinct from 'array' then
    raise exception 'Field tasks must be an array' using errcode = '22023';
  end if;

  for task_item in select value from jsonb_array_elements(p_tasks)
  loop
    task_id := nullif(task_item->>'id', '');
    if task_id is null then
      raise exception 'Every field task must have an id' using errcode = '22023';
    end if;
    assignee_ids := array(
      select jsonb_array_elements_text(
        coalesce(task_item->'assigned_ids', '[]'::jsonb)
      )
    );
    task_date := coalesce(
      nullif(task_item->>'date_key', '')::date,
      current_date
    );
    task_status := case
      when lower(coalesce(task_item->>'status', '')) like '%complete%'
        or lower(coalesce(task_item->>'status', '')) like '%resolved%'
        then 'Completed'
      when lower(coalesce(task_item->>'status', '')) like '%progress%'
        then 'In Progress'
      else 'Pending'
    end;

    select
      coalesce(array_agg(profile.id), '{}'::uuid[]),
      coalesce(
        jsonb_agg(jsonb_build_object(
          'uid', profile.id,
          'name', profile.full_name,
          'role', 'Crew Member',
          'municipalId', profile.municipal_id
        )),
        '[]'::jsonb
      )
    into task_assignees, crew_list
    from public.profiles as profile
    where profile.role = 'crew'
      and not profile.access_blocked
      and profile.municipal_id = any(assignee_ids);

    insert into public.field_tasks (
      id, title, date_key, start_time, end_time, location, description,
      status, assigned_to_uid, crew_members, work_window_start,
      work_window_end, source_report_ids, source_work_order_id, updated_at
    )
    values (
      task_id,
      coalesce(nullif(task_item->>'title', ''), 'Drain maintenance task'),
      task_date,
      nullif(task_item->>'start_time', ''),
      nullif(task_item->>'end_time', ''),
      nullif(task_item->>'location', ''),
      nullif(task_item->>'description', ''),
      task_status,
      task_assignees,
      crew_list,
      task_date::timestamp,
      (task_date + 1)::timestamp,
      array(
        select jsonb_array_elements_text(
          coalesce(task_item->'source_report_ids', '[]'::jsonb)
        )
      ),
      task_id,
      now()
    )
    on conflict (id) do update
      set title = excluded.title,
          date_key = excluded.date_key,
          start_time = excluded.start_time,
          end_time = excluded.end_time,
          location = excluded.location,
          description = excluded.description,
          status = case
            when public.field_tasks.status = 'In Progress'
              and excluded.status = 'Pending'
              then public.field_tasks.status
            else excluded.status
          end,
          assigned_to_uid = excluded.assigned_to_uid,
          crew_members = excluded.crew_members,
          work_window_start = excluded.work_window_start,
          work_window_end = excluded.work_window_end,
          source_report_ids = excluded.source_report_ids,
          source_work_order_id = excluded.source_work_order_id,
          updated_at = now();
  end loop;
end;
$$;

revoke all on function public.sync_dashboard_field_tasks(jsonb)
  from public, anon;
grant execute on function public.sync_dashboard_field_tasks(jsonb)
  to authenticated;

create or replace function public.set_field_task_overdue_rate(
  p_task_id text,
  p_daily_rate integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_daily_rate < 0 or p_daily_rate > 1000 then
    raise exception 'Daily deduction must be between 0 and 1000'
      using errcode = '22023';
  end if;
  update public.field_tasks
  set daily_overdue_deduction = p_daily_rate,
      updated_at = now()
  where id = p_task_id;
  if not found then
    raise exception 'Field task was not found' using errcode = '22023';
  end if;
end;
$$;

revoke all on function public.set_field_task_overdue_rate(text, integer)
  from public, anon;
grant execute on function public.set_field_task_overdue_rate(text, integer)
  to authenticated;

create or replace function public.submit_field_work_update(
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
language plpgsql
security definer
set search_path = public
as $$
declare
  current_uid uuid := auth.uid();
  task_row public.field_tasks%rowtype;
  update_id uuid;
  overdue boolean;
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
  set status = case when status = 'Pending' then 'In Progress' else status end,
      updated_at = now()
  where id = p_task_id;
  return update_id;
end;
$$;

revoke all on function public.submit_field_work_update(
  text, text, text, timestamptz, double precision, double precision,
  double precision, text
) from public, anon;
grant execute on function public.submit_field_work_update(
  text, text, text, timestamptz, double precision, double precision,
  double precision, text
) to authenticated;

alter table public.credit_awards enable row level security;
grant select on public.credit_awards to authenticated;

drop policy if exists "Users read own credit awards"
  on public.credit_awards;
create policy "Users read own credit awards"
  on public.credit_awards
  for select to authenticated
  using (
    public.is_admin()
    or (
      user_id = (select auth.uid())
      and (select public.current_profile_role()) = 'crew'
    )
  );

alter table public.leave_requests enable row level security;
grant select, insert on public.leave_requests to authenticated;

drop policy if exists "Crew and admins read leave requests"
  on public.leave_requests;
create policy "Crew and admins read leave requests"
  on public.leave_requests
  for select to authenticated
  using (
    public.is_admin()
    or (
      user_id = (select auth.uid())
      and (select public.current_profile_role()) = 'crew'
    )
  );

drop policy if exists "Crew create own leave requests"
  on public.leave_requests;
create policy "Crew create own leave requests"
  on public.leave_requests
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and (select public.current_profile_role()) = 'crew'
  );

create or replace function public.grant_field_credits(
  p_task_id text,
  p_crew_uid uuid,
  p_credits integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  task_row public.field_tasks%rowtype;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_credits < 1 or p_credits > 1000 then
    raise exception 'Credits must be between 1 and 1000'
      using errcode = '22023';
  end if;

  select * into task_row
  from public.field_tasks
  where id = p_task_id and p_crew_uid = any(assigned_to_uid);
  if not found then
    raise exception 'Crew member is not assigned to this task'
      using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.field_work_updates
    where task_id = p_task_id and submitted_by_uid = p_crew_uid
  ) then
    raise exception 'Work evidence must be submitted before credits are approved'
      using errcode = '22023';
  end if;

  insert into public.credit_awards (id, user_id, task_id, credits, payload)
  values (
    p_task_id || '_' || p_crew_uid::text,
    p_crew_uid,
    p_task_id,
    p_credits,
    jsonb_build_object(
      'task_title', task_row.title,
      'type', 'award',
      'approved_by_uid', auth.uid()
    )
  )
  on conflict (id) do update
    set credits = excluded.credits,
        payload = excluded.payload,
        created_at = now();
end;
$$;

revoke all on function public.grant_field_credits(text, uuid, integer)
  from public, anon;
grant execute on function public.grant_field_credits(text, uuid, integer)
  to authenticated;

create or replace function public.process_field_overdue_deductions()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  task_item record;
  crew_uid uuid;
  day_to_penalize date;
  inserted_count integer := 0;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;

  for task_item in
    select id, title, date_key, daily_overdue_deduction, assigned_to_uid
    from public.field_tasks
    where date_key < current_date and daily_overdue_deduction > 0
  loop
    for day_to_penalize in
      select generate_series(
        task_item.date_key + 1,
        current_date,
        interval '1 day'
      )::date
    loop
      foreach crew_uid in array task_item.assigned_to_uid loop
        if exists (
          select 1 from public.field_work_updates
          where task_id = task_item.id
            and submitted_by_uid = crew_uid
            and submitted_at::date <= day_to_penalize
        ) then
          continue;
        end if;
        insert into public.credit_awards (
          id, user_id, task_id, credits, payload
        )
        values (
          'overdue_' || task_item.id || '_' || crew_uid::text || '_' ||
            to_char(day_to_penalize, 'YYYY-MM-DD'),
          crew_uid,
          task_item.id,
          -task_item.daily_overdue_deduction,
          jsonb_build_object(
            'task_title', task_item.title,
            'type', 'overduePenalty',
            'penalty_date', day_to_penalize,
            'daily_rate', task_item.daily_overdue_deduction,
            'approved_by_uid', auth.uid()
          )
        )
        on conflict (id) do nothing;
        if found then inserted_count := inserted_count + 1; end if;
      end loop;
    end loop;
  end loop;
  return inserted_count;
end;
$$;

revoke all on function public.process_field_overdue_deductions()
  from public, anon;
grant execute on function public.process_field_overdue_deductions()
  to authenticated;

drop policy if exists "Crew upload assigned work photos"
  on storage.objects;
create policy "Crew upload assigned work photos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'work-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select public.current_profile_role()) = 'crew'
    and exists (
      select 1 from public.field_tasks
      where id = (storage.foldername(name))[2]
        and (select auth.uid()) = any(assigned_to_uid)
    )
  );

drop policy if exists "Crew and admins read work photos"
  on storage.objects;
create policy "Crew and admins read work photos"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'work-photos'
    and (
      public.is_admin()
      or (
        (storage.foldername(name))[1] = (select auth.uid())::text
        and (select public.current_profile_role()) = 'crew'
        and exists (
          select 1 from public.field_tasks
          where id = (storage.foldername(name))[2]
            and (select auth.uid()) = any(assigned_to_uid)
        )
      )
    )
  );

drop policy if exists "Crew delete own assigned work photos"
  on storage.objects;
create policy "Crew delete own assigned work photos"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'work-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select public.current_profile_role()) = 'crew'
    and exists (
      select 1 from public.field_tasks
      where id = (storage.foldername(name))[2]
        and (select auth.uid()) = any(assigned_to_uid)
    )
  );

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'field_tasks', 'field_work_updates', 'leave_requests', 'credit_awards'
  ]
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = target_table
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        target_table
      );
    end if;
  end loop;
end;
$$;
