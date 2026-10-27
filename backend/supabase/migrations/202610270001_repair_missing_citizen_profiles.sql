insert into public.profiles (
  id,
  role,
  full_name,
  municipal_id,
  access_blocked
)
select
  auth_user.id,
  'citizen',
  coalesce(
    nullif(auth_user.raw_user_meta_data ->> 'full_name', ''),
    nullif(split_part(coalesce(auth_user.email, ''), '@', 1), ''),
    'Citizen'
  ),
  null,
  false
from auth.users as auth_user
left join public.profiles as profile
  on profile.id = auth_user.id
where profile.id is null
  and coalesce(auth_user.raw_user_meta_data ->> 'role', 'citizen') = 'citizen'
on conflict (id) do nothing;
