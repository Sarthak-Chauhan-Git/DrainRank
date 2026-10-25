create or replace function public.list_active_crew_profiles()
returns table (
  id uuid,
  municipal_id text,
  full_name text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Administrator access required'
      using errcode = '42501';
  end if;

  return query
  select profile.id, profile.municipal_id, profile.full_name
  from public.profiles as profile
  where profile.role = 'crew'
    and profile.access_blocked is false
    and profile.municipal_id is not null
  order by profile.full_name, profile.municipal_id;
end;
$$;

revoke all on function public.list_active_crew_profiles()
  from public, anon;
grant execute on function public.list_active_crew_profiles()
  to authenticated;
