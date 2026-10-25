alter table public.credit_awards
  drop constraint if exists credit_awards_task_id_fkey;

create or replace function public.validate_credit_award_task_reference()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1 from public.tasks where id = new.task_id
  ) and not exists (
    select 1 from public.field_tasks where id = new.task_id
  ) then
    raise exception 'Credit award task does not exist'
      using errcode = '23503',
            constraint = 'credit_awards_task_id_fkey';
  end if;
  return new;
end;
$$;

revoke all on function public.validate_credit_award_task_reference()
  from public, anon, authenticated;

drop trigger if exists validate_credit_award_task_reference
  on public.credit_awards;
create trigger validate_credit_award_task_reference
before insert or update of task_id on public.credit_awards
for each row
execute function public.validate_credit_award_task_reference();

create or replace function public.delete_orphaned_credit_awards_for_task()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1 from public.tasks where id = old.id
  ) and not exists (
    select 1 from public.field_tasks where id = old.id
  ) then
    delete from public.credit_awards
    where task_id = old.id;
  end if;
  return old;
end;
$$;

revoke all on function public.delete_orphaned_credit_awards_for_task()
  from public, anon, authenticated;

drop trigger if exists delete_orphaned_credit_awards_for_task
  on public.tasks;
create trigger delete_orphaned_credit_awards_for_task
after delete on public.tasks
for each row
execute function public.delete_orphaned_credit_awards_for_task();

drop trigger if exists delete_orphaned_credit_awards_for_task
  on public.field_tasks;
create trigger delete_orphaned_credit_awards_for_task
after delete on public.field_tasks
for each row
execute function public.delete_orphaned_credit_awards_for_task();

notify pgrst, 'reload schema';
