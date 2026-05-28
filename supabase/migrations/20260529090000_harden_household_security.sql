-- Hardens household ownership and membership integrity.
--
-- 1. remove_household_member now scopes the delete to an explicit household so
--    an owner of several households can no longer remove a member from the
--    wrong household (an arbitrary match was picked previously).
-- 2. Members can leave a household on their own via leave_household / a
--    self-delete policy, while the sole owner is prevented from orphaning it.
-- 3. households.owner_id can no longer be reassigned through a direct update,
--    keeping household_members 'owner' and households.owner_id consistent.

-- === C22: scope member removal to a specific household ===

-- Drop the legacy single-argument overload; callers now pass the household id.
drop function if exists public.remove_household_member(uuid);

create or replace function public.remove_household_member(
  target_household_id uuid,
  target_user_id uuid
)
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

  if target_user_id = current_user_id then
    raise exception 'Cannot remove yourself' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.household_members o
    where o.household_id = target_household_id
      and o.user_id = current_user_id
      and o.role = 'owner'
  ) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.household_members hm
    where hm.household_id = target_household_id
      and hm.user_id = target_user_id
      and hm.role = 'member'
  ) then
    raise exception 'Not authorized or target is not a member' using errcode = '42501';
  end if;

  delete from public.household_members
  where household_id = target_household_id
    and user_id = target_user_id
    and role = 'member';
end;
$$;

revoke all on function public.remove_household_member(uuid, uuid) from public;
revoke all on function public.remove_household_member(uuid, uuid) from anon;
grant execute on function public.remove_household_member(uuid, uuid) to authenticated;

-- === C40: let a member leave a household on their own ===

-- A member may delete their own membership row. Owners must use dissolve or a
-- transfer path so they cannot silently orphan the household by leaving.
create policy "household_members_delete_self" on public.household_members
  for delete to authenticated
  using (user_id = (select auth.uid()) and role <> 'owner');

create or replace function public.leave_household(target_household_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := (select auth.uid());
  current_role text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select hm.role into current_role
  from public.household_members hm
  where hm.household_id = target_household_id
    and hm.user_id = current_user_id;

  if current_role is null then
    raise exception 'Not a member of this household' using errcode = '42501';
  end if;

  if current_role = 'owner' then
    -- The sole owner cannot leave; doing so would orphan the household.
    if not exists (
      select 1 from public.household_members hm
      where hm.household_id = target_household_id
        and hm.role = 'owner'
        and hm.user_id <> current_user_id
    ) then
      raise exception 'Sole owner cannot leave; transfer or dissolve the household instead'
        using errcode = 'P0001';
    end if;
  end if;

  delete from public.household_members
  where household_id = target_household_id
    and user_id = current_user_id;
end;
$$;

revoke all on function public.leave_household(uuid) from public;
revoke all on function public.leave_household(uuid) from anon;
grant execute on function public.leave_household(uuid) to authenticated;

-- === C41: forbid reassigning households.owner_id via a direct update ===

drop policy if exists "households_update_owner" on public.households;

create policy "households_update_owner" on public.households
  for update to authenticated
  using (app_private.is_household_owner(id))
  with check (
    app_private.is_household_owner(id)
    and owner_id = (select auth.uid())
  );

-- Defense in depth: block owner_id reassignment on every update path
-- (including service-role / SECURITY DEFINER), independent of RLS.
create or replace function app_private.forbid_household_owner_change()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.owner_id is distinct from old.owner_id then
    raise exception 'household owner_id cannot be reassigned' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists households_forbid_owner_change on public.households;

create trigger households_forbid_owner_change
  before update on public.households
  for each row
  execute function app_private.forbid_household_owner_change();

-- === U14: invites stuck as 'pending' past expiry ===
--
-- No code path ever sets status = 'expired'; pending invites simply linger.
-- This is intentionally left as-is: every read path
-- (list_pending_household_invites, list_owner_pending_invites,
-- preview_household_invite, accept_household_invite*) already filters on
-- expires_at > now(), so an unexpired-by-status row is never surfaced or
-- accepted. Introducing a scheduled transition would add surface area
-- (pg_cron dependency) without changing observable behaviour, so it is
-- deferred. Documented here as a known, low-risk gap.
