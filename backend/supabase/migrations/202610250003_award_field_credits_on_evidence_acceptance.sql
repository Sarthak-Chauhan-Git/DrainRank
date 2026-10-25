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

  if p_decision = 'accept' then
    insert into public.credit_awards (id, user_id, task_id, credits, payload)
    select
      evidence.task_id || '_' || evidence.submitted_by_uid::text,
      evidence.submitted_by_uid,
      evidence.task_id,
      10,
      jsonb_build_object(
        'task_title', task.title,
        'type', 'award',
        'approved_by_uid', auth.uid()
      )
    from public.field_tasks as task
    where task.id = evidence.task_id
    on conflict (id) do update
      set credits = excluded.credits,
          payload = excluded.payload,
          created_at = now();
  end if;

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
