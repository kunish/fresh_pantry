create or replace function public.list_household_members(target_household_id uuid)
returns table (
  household_id uuid,
  user_id uuid,
  role text,
  email text
)
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
    from public.household_members hm
    where hm.household_id = target_household_id
      and hm.user_id = current_user_id
  ) then
    raise exception 'Household access denied' using errcode = '42501';
  end if;

  return query
  select
    hm.household_id,
    hm.user_id,
    hm.role,
    coalesce(p.email, u.email, '')
  from public.household_members hm
  left join public.profiles p on p.id = hm.user_id
  left join auth.users u on u.id = hm.user_id
  where hm.household_id = target_household_id
  order by
    case hm.role when 'owner' then 0 else 1 end,
    lower(coalesce(p.email, u.email, '')),
    hm.joined_at;
end;
$$;

revoke all on function public.list_household_members(uuid) from public;
revoke all on function public.list_household_members(uuid) from anon;
grant execute on function public.list_household_members(uuid) to authenticated;
