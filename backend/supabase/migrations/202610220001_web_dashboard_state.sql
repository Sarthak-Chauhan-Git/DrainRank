create table if not exists public.dashboard_admins (
  user_id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.dashboard_admins enable row level security;
revoke all on public.dashboard_admins from anon, authenticated;
grant select on public.dashboard_admins to authenticated;

drop policy if exists "Dashboard admins can read their own membership"
  on public.dashboard_admins;
create policy "Dashboard admins can read their own membership"
  on public.dashboard_admins
  for select
  to authenticated
  using (user_id = (select auth.uid()));

create table if not exists public.web_dashboard_state (
  singleton_id text primary key check (singleton_id = 'municipal'),
  payload jsonb not null,
  revision bigint not null default 1,
  updated_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.web_dashboard_state enable row level security;
revoke all on public.web_dashboard_state from anon, authenticated;
grant select on public.web_dashboard_state to authenticated;

drop policy if exists "Dashboard admins can read dashboard state"
  on public.web_dashboard_state;
create policy "Dashboard admins can read dashboard state"
  on public.web_dashboard_state
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.dashboard_admins
      where dashboard_admins.user_id = (select auth.uid())
    )
  );

create or replace function public.save_web_dashboard_state(
  p_payload jsonb,
  p_expected_revision bigint
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  current_revision bigint;
begin
  if auth.uid() is null or not exists (
    select 1
    from public.dashboard_admins
    where dashboard_admins.user_id = auth.uid()
  ) then
    raise exception 'Dashboard administrator access required'
      using errcode = '42501';
  end if;

  select revision
  into current_revision
  from public.web_dashboard_state
  where singleton_id = 'municipal'
  for update;

  if not found then
    if p_expected_revision <> 0 then
      raise exception 'Dashboard state changed. Reload before saving.'
        using errcode = '40001';
    end if;
    begin
      insert into public.web_dashboard_state (
        singleton_id,
        payload,
        revision,
        updated_by
      )
      values ('municipal', p_payload, 1, auth.uid());
      return 1;
    exception
      when unique_violation then
        raise exception 'Dashboard state changed. Reload before saving.'
          using errcode = '40001';
    end;
  end if;

  if current_revision <> p_expected_revision then
    raise exception 'Dashboard state changed. Reload before saving.'
      using errcode = '40001';
  end if;

  update public.web_dashboard_state
  set payload = p_payload,
      revision = current_revision + 1,
      updated_by = auth.uid(),
      updated_at = now()
  where singleton_id = 'municipal'
  returning revision into current_revision;

  return current_revision;
end;
$$;

revoke all on function public.save_web_dashboard_state(jsonb, bigint)
  from public, anon;
grant execute on function public.save_web_dashboard_state(jsonb, bigint)
  to authenticated;

grant select on public.citizen_reports to authenticated;
drop policy if exists "Dashboard admins can read citizen reports"
  on public.citizen_reports;
create policy "Dashboard admins can read citizen reports"
  on public.citizen_reports
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.dashboard_admins
      where dashboard_admins.user_id = (select auth.uid())
    )
  );
