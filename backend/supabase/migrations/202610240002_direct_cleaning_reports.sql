create table if not exists public.direct_cleaning_reports (
  report_id text primary key,
  reporter_uid uuid not null references auth.users(id) on delete cascade,
  issue_category text not null,
  linked_drain_id text not null default 'PROVISIONAL-PIN',
  is_urgent_flagged boolean not null default false,
  estimated_priority_score double precision not null default 0
    check (estimated_priority_score between 0 and 100),
  description text not null,
  ward text not null,
  location_description text not null,
  latitude double precision not null,
  longitude double precision not null,
  accuracy_meters double precision not null,
  photo_path text not null,
  captured_at timestamptz not null,
  review_status text not null default 'pending'
    check (review_status in ('pending', 'verified', 'rejected')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint direct_cleaning_reports_category_check
    check (issue_category in (
      'blocked_drain', 'waterlogging', 'overflow', 'other'
    )),
  constraint direct_cleaning_reports_location_check
    check (
      latitude between -90 and 90
      and longitude between -180 and 180
      and accuracy_meters >= 0
    )
);

alter table public.direct_cleaning_reports
  add column if not exists linked_drain_id text not null default 'PROVISIONAL-PIN',
  add column if not exists is_urgent_flagged boolean not null default false,
  add column if not exists estimated_priority_score double precision not null
    default 0 check (estimated_priority_score between 0 and 100);

create index if not exists direct_cleaning_reports_created_at_idx
  on public.direct_cleaning_reports (created_at desc);

alter table public.direct_cleaning_reports enable row level security;
grant select on public.direct_cleaning_reports to authenticated;

drop policy if exists "Crew and admins read direct cleaning reports"
  on public.direct_cleaning_reports;
create policy "Crew and admins read direct cleaning reports"
  on public.direct_cleaning_reports
  for select to authenticated
  using (
    reporter_uid = (select auth.uid())
    or (select public.is_admin())
  );

create table if not exists public.direct_cleaning_report_credits (
  report_id text primary key
    references public.direct_cleaning_reports(report_id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  credits integer not null check (credits between 1 and 1000),
  ward text not null,
  approved_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

alter table public.direct_cleaning_report_credits enable row level security;
grant select on public.direct_cleaning_report_credits to authenticated;

drop policy if exists "Users read own direct report credits"
  on public.direct_cleaning_report_credits;
create policy "Users read own direct report credits"
  on public.direct_cleaning_report_credits
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select public.is_admin())
  );

create or replace function public.list_direct_report_wards()
returns text[]
language plpgsql
security definer
set search_path = public
as $$
declare
  wards text[];
begin
  if auth.uid() is null
    or (select public.current_profile_role()) is distinct from 'crew' then
    raise exception 'Active crew access required' using errcode = '42501';
  end if;

  select array_agg(ward_name order by ward_name)
  into wards
  from jsonb_object_keys(
    coalesce(
      (select payload->'creditPolicy'->'wardAllowances'
       from public.dashboard_state where id = 'municipal'),
      '{}'::jsonb
    )
  ) as ward_name;

  if coalesce(array_length(wards, 1), 0) = 0 then
    raise exception 'No ward credit rates are configured in the dashboard'
      using errcode = '22023';
  end if;
  return wards;
end;
$$;

revoke all on function public.list_direct_report_wards()
  from public, anon;
grant execute on function public.list_direct_report_wards() to authenticated;

drop function if exists public.submit_direct_cleaning_report(
  text, text, text, text, text, double precision, double precision,
  double precision, text, timestamptz
);

create or replace function public.submit_direct_cleaning_report(
  p_report_id text,
  p_issue_category text,
  p_description text,
  p_ward text,
  p_location_description text,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_photo_path text,
  p_captured_at timestamptz,
  p_linked_drain_id text,
  p_is_urgent_flagged boolean,
  p_estimated_priority_score double precision
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_uid uuid := auth.uid();
  available_wards text[];
begin
  if current_uid is null
    or (select public.current_profile_role()) is distinct from 'crew' then
    raise exception 'Active crew access required' using errcode = '42501';
  end if;
  if p_report_id is null or p_report_id !~ '^DCR-[A-Za-z0-9-]{8,80}$' then
    raise exception 'Invalid report ID' using errcode = '22023';
  end if;
  if p_issue_category not in (
    'blocked_drain', 'waterlogging', 'overflow', 'other'
  ) then
    raise exception 'Invalid direct cleaning issue category'
      using errcode = '22023';
  end if;
  if p_description is null or length(trim(p_description)) = 0
    or length(trim(p_location_description)) = 0 then
    raise exception 'Location and issue details are required'
      using errcode = '22023';
  end if;
  if p_latitude is null or p_latitude not between -90 and 90
    or p_longitude is null or p_longitude not between -180 and 180
    or p_accuracy_meters is null or p_accuracy_meters < 0 then
    raise exception 'Valid GPS coordinates and accuracy are required'
      using errcode = '22023';
  end if;
  if p_photo_path is distinct from current_uid::text || '/' || p_report_id || '.jpg'
    or p_captured_at is null then
    raise exception 'A valid GPS-tagged report photo is required'
      using errcode = '22023';
  end if;
  if p_linked_drain_id is null
    or length(trim(p_linked_drain_id)) = 0
    or p_is_urgent_flagged is null
    or p_estimated_priority_score is null
    or p_estimated_priority_score not between 0 and 100 then
    raise exception 'A valid location priority assessment is required'
      using errcode = '22023';
  end if;

  select array_agg(ward_name)
  into available_wards
  from jsonb_object_keys(
    coalesce(
      (select payload->'creditPolicy'->'wardAllowances'
       from public.dashboard_state where id = 'municipal'),
      '{}'::jsonb
    )
  ) as ward_name;
  if p_ward is null or not (p_ward = any(coalesce(available_wards, '{}'))) then
    raise exception 'Select a configured ward'
      using errcode = '22023';
  end if;

  insert into public.direct_cleaning_reports (
    report_id, reporter_uid, issue_category, linked_drain_id,
    is_urgent_flagged, estimated_priority_score, description, ward,
    location_description, latitude, longitude, accuracy_meters,
    photo_path, captured_at
  )
  values (
    p_report_id, current_uid, p_issue_category, p_linked_drain_id,
    p_is_urgent_flagged, p_estimated_priority_score, trim(p_description), p_ward,
    trim(p_location_description), p_latitude, p_longitude, p_accuracy_meters,
    p_photo_path, p_captured_at
  );
end;
$$;

revoke all on function public.submit_direct_cleaning_report(
  text, text, text, text, text, double precision, double precision,
  double precision, text, timestamptz, text, boolean, double precision
) from public, anon;
grant execute on function public.submit_direct_cleaning_report(
  text, text, text, text, text, double precision, double precision,
  double precision, text, timestamptz, text, boolean, double precision
) to authenticated;

create or replace function public.review_direct_cleaning_report(
  p_report_id text,
  p_decision text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  report_row public.direct_cleaning_reports%rowtype;
  policy_payload jsonb;
  credit_amount integer;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  if p_decision not in ('verify', 'reject') then
    raise exception 'Decision must be verify or reject' using errcode = '22023';
  end if;

  select * into report_row
  from public.direct_cleaning_reports
  where report_id = p_report_id
  for update;
  if not found then
    raise exception 'Direct cleaning report not found' using errcode = 'P0002';
  end if;
  if report_row.review_status <> 'pending' then
    raise exception 'This report has already been reviewed'
      using errcode = '22023';
  end if;

  if p_decision = 'reject' then
    update public.direct_cleaning_reports
    set review_status = 'rejected',
        reviewed_by = auth.uid(),
        reviewed_at = now()
    where report_id = p_report_id;
    return 0;
  end if;

  select payload->'creditPolicy'
  into policy_payload
  from public.dashboard_state
  where id = 'municipal';
  credit_amount := coalesce(
    nullif(
      policy_payload->'wardAllowances'->report_row.ward
        ->>'successfulCleaning',
      ''
    )::integer,
    nullif(policy_payload->>'baseCleaning', '')::integer
  );
  if credit_amount is null or credit_amount not between 1 and 1000 then
    raise exception 'The configured cleaning credit rate is invalid'
      using errcode = '22023';
  end if;

  update public.direct_cleaning_reports
  set review_status = 'verified',
      reviewed_by = auth.uid(),
      reviewed_at = now()
  where report_id = p_report_id;

  insert into public.direct_cleaning_report_credits (
    report_id, user_id, credits, ward, approved_by
  )
  values (
    p_report_id, report_row.reporter_uid, credit_amount,
    report_row.ward, auth.uid()
  );
  return credit_amount;
end;
$$;

revoke all on function public.review_direct_cleaning_report(text, text)
  from public, anon;
grant execute on function public.review_direct_cleaning_report(text, text)
  to authenticated;

insert into storage.buckets (id, name, public)
values ('field-direct-reports', 'field-direct-reports', false)
on conflict (id) do update set public = false;

drop policy if exists "Crew upload own direct report photos"
  on storage.objects;
create policy "Crew upload own direct report photos"
  on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'field-direct-reports'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select public.current_profile_role()) = 'crew'
  );

drop policy if exists "Crew and admins read direct report photos"
  on storage.objects;
create policy "Crew and admins read direct report photos"
  on storage.objects
  for select to authenticated
  using (
    bucket_id = 'field-direct-reports'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or (select public.is_admin())
    )
  );

drop policy if exists "Crew delete own direct report photos"
  on storage.objects;
create policy "Crew delete own direct report photos"
  on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'field-direct-reports'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and (select public.current_profile_role()) = 'crew'
  );

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'direct_cleaning_reports'
  ) then
    alter publication supabase_realtime
      add table public.direct_cleaning_reports;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'direct_cleaning_report_credits'
  ) then
    alter publication supabase_realtime
      add table public.direct_cleaning_report_credits;
  end if;
end;
$$;

notify pgrst, 'reload schema';
