create schema if not exists app_private;
revoke all on schema app_private from public;
grant usage on schema app_private to authenticated;

create extension if not exists pgcrypto with schema extensions;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null references auth.users(id) on delete cascade,
  default_storage_area text not null default 'fridge',
  category_preferences jsonb not null default '{}'::jsonb,
  unit_preferences jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.household_members (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (household_id, user_id)
);

create table public.household_invites (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  email text not null,
  token_hash text not null unique,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'expired', 'revoked')),
  expires_at timestamptz not null,
  accepted_by uuid references auth.users(id),
  accepted_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name text not null,
  quantity text not null,
  unit text not null,
  image_url text not null default '',
  freshness_percent numeric not null default 1,
  state text not null default 'fresh',
  expiry_label text,
  category text,
  barcode text,
  storage text not null default 'fridge',
  expiry_date timestamptz,
  added_at timestamptz,
  shelf_life_days integer,
  version integer not null default 1,
  client_id text,
  client_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.shopping_items (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name text not null,
  detail text not null default '',
  image_url text,
  category text not null default '其他',
  is_checked boolean not null default false,
  version integer not null default 1,
  client_id text,
  client_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.custom_recipes (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  payload jsonb not null,
  version integer not null default 1,
  client_id text,
  client_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.sync_events (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  entity_type text not null check (entity_type in ('inventory_item', 'shopping_item', 'custom_recipe', 'household_config')),
  entity_id uuid not null,
  operation text not null,
  patch jsonb not null default '{}'::jsonb,
  base_version integer,
  result_version integer,
  client_id text not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create index inventory_items_household_updated_idx on public.inventory_items (household_id, updated_at);
create index shopping_items_household_updated_idx on public.shopping_items (household_id, updated_at);
create index custom_recipes_household_updated_idx on public.custom_recipes (household_id, updated_at);
create index sync_events_household_created_idx on public.sync_events (household_id, created_at);
create index household_invites_email_status_idx on public.household_invites (lower(email), status);

grant usage on schema public to authenticated;
grant select, insert, update, delete on
  public.profiles,
  public.households,
  public.household_members,
  public.household_invites,
  public.inventory_items,
  public.shopping_items,
  public.custom_recipes,
  public.sync_events
to authenticated;

create or replace function app_private.is_household_member(target_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.household_members hm
    where hm.household_id = target_household_id
      and hm.user_id = (select auth.uid())
  );
$$;

create or replace function app_private.is_household_owner(target_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.household_members hm
    where hm.household_id = target_household_id
      and hm.user_id = (select auth.uid())
      and hm.role = 'owner'
  );
$$;

create or replace function app_private.is_household_owner_record(target_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.households h
    where h.id = target_household_id
      and h.owner_id = (select auth.uid())
  );
$$;

revoke all on function app_private.is_household_member(uuid) from public;
revoke all on function app_private.is_household_owner(uuid) from public;
revoke all on function app_private.is_household_owner_record(uuid) from public;
grant execute on function app_private.is_household_member(uuid) to authenticated;
grant execute on function app_private.is_household_owner(uuid) to authenticated;
grant execute on function app_private.is_household_owner_record(uuid) to authenticated;

alter table public.profiles enable row level security;
alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.household_invites enable row level security;
alter table public.inventory_items enable row level security;
alter table public.shopping_items enable row level security;
alter table public.custom_recipes enable row level security;
alter table public.sync_events enable row level security;

create policy "profiles_select_self" on public.profiles
  for select to authenticated
  using ((select auth.uid()) = id);

create policy "profiles_insert_self" on public.profiles
  for insert to authenticated
  with check ((select auth.uid()) = id);

create policy "profiles_update_self" on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create policy "households_select_member" on public.households
  for select to authenticated
  using (app_private.is_household_member(id));

create policy "households_insert_owner" on public.households
  for insert to authenticated
  with check ((select auth.uid()) = owner_id);

create policy "households_update_owner" on public.households
  for update to authenticated
  using (app_private.is_household_owner(id))
  with check (app_private.is_household_owner(id));

create policy "household_members_select_member" on public.household_members
  for select to authenticated
  using (app_private.is_household_member(household_id));

create policy "household_members_insert_owner_or_existing_owner" on public.household_members
  for insert to authenticated
  with check (
    app_private.is_household_owner(household_id)
    or (
      role = 'owner'
      and user_id = (select auth.uid())
      and app_private.is_household_owner_record(household_id)
    )
  );

create policy "household_members_delete_owner" on public.household_members
  for delete to authenticated
  using (app_private.is_household_owner(household_id) and role = 'member');

create policy "household_invites_select_owner" on public.household_invites
  for select to authenticated
  using (app_private.is_household_owner(household_id));

create policy "household_invites_insert_owner" on public.household_invites
  for insert to authenticated
  with check (app_private.is_household_owner(household_id) and created_by = (select auth.uid()));

create policy "household_invites_update_owner" on public.household_invites
  for update to authenticated
  using (app_private.is_household_owner(household_id) and status <> 'accepted')
  with check (
    app_private.is_household_owner(household_id)
    and status <> 'accepted'
    and accepted_by is null
    and accepted_at is null
  );

create policy "inventory_items_member_all" on public.inventory_items
  for all to authenticated
  using (app_private.is_household_member(household_id))
  with check (app_private.is_household_member(household_id));

create policy "shopping_items_member_all" on public.shopping_items
  for all to authenticated
  using (app_private.is_household_member(household_id))
  with check (app_private.is_household_member(household_id));

create policy "custom_recipes_member_all" on public.custom_recipes
  for all to authenticated
  using (app_private.is_household_member(household_id))
  with check (app_private.is_household_member(household_id));

create policy "sync_events_select_member" on public.sync_events
  for select to authenticated
  using (app_private.is_household_member(household_id));

create policy "sync_events_insert_member_self" on public.sync_events
  for insert to authenticated
  with check (app_private.is_household_member(household_id) and created_by = (select auth.uid()));

create or replace function public.accept_household_invite(invite_token_hash text)
returns public.household_members
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := (select auth.uid());
  current_email text := lower(coalesce((select auth.jwt() ->> 'email'), ''));
  invite_record public.household_invites;
  accepted_member public.household_members;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select *
  into invite_record
  from public.household_invites
  where token_hash = invite_token_hash
  for update;

  if not found
    or invite_record.status <> 'pending'
    or invite_record.expires_at <= now()
  then
    raise exception 'Invite is not available' using errcode = 'P0001';
  end if;

  if current_email = '' or lower(invite_record.email) <> current_email then
    raise exception 'Invite email does not match authenticated user' using errcode = '42501';
  end if;

  insert into public.household_members (household_id, user_id, role)
  values (invite_record.household_id, current_user_id, 'member')
  on conflict (household_id, user_id) do nothing
  returning *
  into accepted_member;

  if accepted_member.household_id is null then
    select *
    into accepted_member
    from public.household_members
    where household_id = invite_record.household_id
      and user_id = current_user_id;
  end if;

  update public.household_invites
  set status = 'accepted',
      accepted_by = current_user_id,
      accepted_at = now()
  where id = invite_record.id;

  return accepted_member;
end;
$$;

revoke all on function public.accept_household_invite(text) from public;
revoke all on function public.accept_household_invite(text) from anon;
grant execute on function public.accept_household_invite(text) to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'inventory_items'
    ) then
      execute 'alter publication supabase_realtime add table public.inventory_items';
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'shopping_items'
    ) then
      execute 'alter publication supabase_realtime add table public.shopping_items';
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'custom_recipes'
    ) then
      execute 'alter publication supabase_realtime add table public.custom_recipes';
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'sync_events'
    ) then
      execute 'alter publication supabase_realtime add table public.sync_events';
    end if;
  end if;
end;
$$;
