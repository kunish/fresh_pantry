create or replace function public.preview_household_invite(invite_token_hash text)
returns table (
  household_id uuid,
  household_name text,
  owner_email text,
  invited_email text,
  member_count integer,
  inventory_count integer,
  shopping_count integer,
  custom_recipe_count integer,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := (select auth.uid());
  current_email text := lower(coalesce((select auth.jwt() ->> 'email'), ''));
  invite_record public.household_invites;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select *
  into invite_record
  from public.household_invites
  where token_hash = invite_token_hash;

  if not found
    or invite_record.status <> 'pending'
    or invite_record.expires_at <= now()
  then
    raise exception 'Invite is not available' using errcode = 'P0001';
  end if;

  if current_email = '' or lower(invite_record.email) <> current_email then
    raise exception 'Invite email does not match authenticated user' using errcode = '42501';
  end if;

  return query
  select
    h.id,
    h.name,
    coalesce(p.email, u.email, ''),
    invite_record.email,
    (
      select count(*)::integer
      from public.household_members hm
      where hm.household_id = invite_record.household_id
    ),
    (
      select count(*)::integer
      from public.inventory_items ii
      where ii.household_id = invite_record.household_id
        and ii.deleted_at is null
    ),
    (
      select count(*)::integer
      from public.shopping_items si
      where si.household_id = invite_record.household_id
        and si.deleted_at is null
    ),
    (
      select count(*)::integer
      from public.custom_recipes cr
      where cr.household_id = invite_record.household_id
        and cr.deleted_at is null
    ),
    invite_record.expires_at
  from public.households h
  left join public.profiles p on p.id = h.owner_id
  left join auth.users u on u.id = h.owner_id
  where h.id = invite_record.household_id;
end;
$$;

revoke all on function public.preview_household_invite(text) from public;
revoke all on function public.preview_household_invite(text) from anon;
grant execute on function public.preview_household_invite(text) to authenticated;
