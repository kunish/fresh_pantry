create or replace function public.dissolve_household(target_household_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if not exists (
    select 1
    from public.households h
    join public.household_members hm on hm.household_id = h.id
    where h.id = target_household_id
      and h.owner_id = current_user_id
      and hm.user_id = current_user_id
      and hm.role = 'owner'
  ) then
    raise exception 'Not authorized or household not found' using errcode = '42501';
  end if;

  delete from public.households h
  where h.id = target_household_id
    and h.owner_id = current_user_id;
end;
$$;

revoke all on function public.dissolve_household(uuid) from public;
revoke all on function public.dissolve_household(uuid) from anon;
grant execute on function public.dissolve_household(uuid) to authenticated;
