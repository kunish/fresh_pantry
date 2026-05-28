begin;

select plan(82);

create or replace function pg_temp.authenticate_as(user_id uuid, user_email text)
returns void
language sql
as $$
  select set_config('request.jwt.claim.sub', user_id::text, true);
  select set_config('request.jwt.claim.email', user_email, true);
  select set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', user_id::text,
      'email', user_email,
      'role', 'authenticated'
    )::text,
    true
  );
$$;

create or replace function pg_temp.clear_auth()
returns void
language sql
as $$
  select set_config('request.jwt.claim.sub', '', true);
  select set_config('request.jwt.claim.email', '', true);
  select set_config('request.jwt.claims', '{}'::text, true);
$$;

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', 'authenticated', 'authenticated', 'owner@example.com', extensions.crypt('password', extensions.gen_salt('bf')), now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '22222222-2222-2222-2222-222222222222', 'authenticated', 'authenticated', 'member@example.com', extensions.crypt('password', extensions.gen_salt('bf')), now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '33333333-3333-3333-3333-333333333333', 'authenticated', 'authenticated', 'outsider@example.com', extensions.crypt('password', extensions.gen_salt('bf')), now(), now(), now())
on conflict (id) do nothing;

insert into public.households (id, name, owner_id)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Kunish Kitchen', '11111111-1111-1111-1111-111111111111')
on conflict (id) do nothing;

insert into public.household_members (household_id, user_id, role)
values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'member')
on conflict (household_id, user_id) do nothing;

set local role authenticated;

select pg_temp.authenticate_as('11111111-1111-1111-1111-111111111111', 'owner@example.com');

select is(
  (select count(*) from public.households where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  1::bigint,
  'owner can read household'
);

select lives_ok(
  $$
    insert into public.inventory_items (household_id, name, quantity, unit, storage)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Milk', '1', 'box', 'fridge')
  $$,
  'owner can write inventory'
);

-- C4/C43: the BEFORE UPDATE trigger makes `version` server-authoritative.
select is(
  (select version from public.inventory_items where name = 'Milk'),
  1,
  'inserted inventory row keeps default version 1 (trigger is update-only)'
);

select lives_ok(
  $$
    update public.inventory_items set quantity = '2' where name = 'Milk'
  $$,
  'owner can update inventory'
);

select is(
  (select version from public.inventory_items where name = 'Milk'),
  2,
  'update bumps version to OLD.version + 1'
);

-- Even when the client sends a stale/lower version, the trigger overrides it.
select lives_ok(
  $$
    update public.inventory_items set quantity = '3', version = 1 where name = 'Milk'
  $$,
  'owner can update inventory while sending a stale version'
);

select is(
  (select version from public.inventory_items where name = 'Milk'),
  3,
  'client-sent stale version is overridden by the server bump'
);

select pg_temp.authenticate_as('22222222-2222-2222-2222-222222222222', 'member@example.com');

select is(
  (select count(*) from public.inventory_items where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  1::bigint,
  'member can read shared inventory'
);

select is(
  (
    select string_agg(email || ':' || role, ',' order by email)
    from public.list_household_members('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
  ),
  'member@example.com:member,owner@example.com:owner',
  'member can list household members with emails'
);

select lives_ok(
  $$
    insert into public.shopping_items (household_id, name, detail, category)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Eggs', '12 count', 'Dairy')
  $$,
  'member can write shopping item'
);

select lives_ok(
  $$
    insert into public.sync_events (
      household_id,
      entity_type,
      entity_id,
      operation,
      client_id,
      created_by
    )
    values (
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'shopping_item',
      'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      'insert',
      'member-client',
      '22222222-2222-2222-2222-222222222222'
    )
  $$,
  'member can write own sync event'
);

select pg_temp.authenticate_as('33333333-3333-3333-3333-333333333333', 'outsider@example.com');

select is(
  (select count(*) from public.households where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0::bigint,
  'non-member cannot read household'
);

select throws_ok(
  $$ select * from public.list_household_members('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa') $$,
  '42501',
  'Household access denied',
  'non-member cannot list household members'
);

select is(
  (select count(*) from public.inventory_items where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0::bigint,
  'non-member cannot read inventory'
);

select throws_ok(
  $$
    insert into public.inventory_items (household_id, name, quantity, unit, storage)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Butter', '1', 'pack', 'fridge')
  $$,
  '42501',
  'new row violates row-level security policy for table "inventory_items"',
  'non-member cannot write inventory'
);

select throws_ok(
  $$
    insert into public.custom_recipes (household_id, payload)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '{"name":"Soup"}'::jsonb)
  $$,
  '42501',
  'new row violates row-level security policy for table "custom_recipes"',
  'non-member cannot write custom recipe'
);

select throws_ok(
  $$
    insert into public.sync_events (
      household_id,
      entity_type,
      entity_id,
      operation,
      client_id,
      created_by
    )
    values (
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      'inventory_item',
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      'insert',
      'outsider-client',
      '33333333-3333-3333-3333-333333333333'
    )
  $$,
  '42501',
  'new row violates row-level security policy for table "sync_events"',
  'non-member cannot write sync event'
);

select throws_ok(
  $$
    insert into public.household_members (household_id, user_id, role)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '33333333-3333-3333-3333-333333333333', 'owner')
  $$,
  '42501',
  'new row violates row-level security policy for table "household_members"',
  'non-owner cannot self-add as household owner'
);

select pg_temp.authenticate_as('11111111-1111-1111-1111-111111111111', 'owner@example.com');

insert into public.household_invites (
  household_id,
  email,
  token_hash,
  expires_at,
  created_by
)
values (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'outsider@example.com',
  'outsider-invite-token',
  now() + interval '7 days',
  '11111111-1111-1111-1111-111111111111'
);

insert into public.household_invites (
  id,
  household_id,
  email,
  token_hash,
  expires_at,
  created_by
)
values (
  'dddddddd-dddd-dddd-dddd-dddddddddddd',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'outsider@example.com',
  'outsider-app-reminder-token',
  now() + interval '7 days',
  '11111111-1111-1111-1111-111111111111'
);

insert into public.household_invites (
  id,
  household_id,
  email,
  token_hash,
  expires_at,
  created_by
)
values (
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  null,
  'open-invite-token',
  now() + interval '7 days',
  '11111111-1111-1111-1111-111111111111'
);

insert into public.household_invites (
  household_id,
  email,
  token_hash,
  status,
  expires_at,
  created_by
)
values
  (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'outsider@example.com',
    'expired-invite-token',
    'pending',
    now() - interval '1 minute',
    '11111111-1111-1111-1111-111111111111'
  ),
  (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'outsider@example.com',
    'revoked-invite-token',
    'revoked',
    now() + interval '7 days',
    '11111111-1111-1111-1111-111111111111'
  );

select pg_temp.clear_auth();

select throws_ok(
  $$ select public.accept_household_invite('outsider-invite-token') $$,
  '28000',
  'Authentication required',
  'invite acceptance requires auth uid'
);

select ok(
  not has_function_privilege('anon', 'public.accept_household_invite(text)', 'execute'),
  'anon cannot execute invite acceptance rpc'
);

select ok(
  not has_function_privilege('anon', 'public.preview_household_invite(text)', 'execute'),
  'anon cannot execute invite preview rpc'
);

select ok(
  not has_function_privilege('anon', 'public.list_pending_household_invites()', 'execute'),
  'anon cannot execute pending invite list rpc'
);

select ok(
  not has_function_privilege('anon', 'public.accept_household_invite_by_id(uuid)', 'execute'),
  'anon cannot execute invite acceptance by id rpc'
);

select ok(
  not has_function_privilege('anon', 'public.list_household_members(uuid)', 'execute'),
  'anon cannot execute household member list rpc'
);

select throws_ok(
  $$ select public.preview_household_invite('outsider-invite-token') $$,
  '28000',
  'Authentication required',
  'invite preview requires auth uid'
);

select throws_ok(
  $$ select * from public.list_pending_household_invites() $$,
  '28000',
  'Authentication required',
  'pending invite list requires auth uid'
);

select throws_ok(
  $$ select public.remove_household_member('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, '22222222-2222-2222-2222-222222222222'::uuid) $$,
  '28000',
  'Authentication required',
  'remove_household_member requires auth uid'
);

select throws_ok(
  $$ select public.revoke_household_invite('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'::uuid) $$,
  '28000',
  'Authentication required',
  'revoke_household_invite requires auth uid'
);

select throws_ok(
  $$ select * from public.list_owner_pending_invites('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid) $$,
  '28000',
  'Authentication required',
  'list_owner_pending_invites requires auth uid'
);

select pg_temp.authenticate_as('22222222-2222-2222-2222-222222222222', 'member@example.com');

select throws_ok(
  $$ select public.preview_household_invite('outsider-invite-token') $$,
  '42501',
  'Invite email does not match authenticated user',
  'wrong email cannot preview invite'
);

select throws_ok(
  $$ select public.accept_household_invite('outsider-invite-token') $$,
  '42501',
  'Invite email does not match authenticated user',
  'wrong email cannot accept invite'
);

select is(
  (select count(*) from public.list_pending_household_invites()),
  0::bigint,
  'wrong email cannot list email-bound pending invite reminders'
);

select throws_ok(
  $$ select public.accept_household_invite_by_id('dddddddd-dddd-dddd-dddd-dddddddddddd'::uuid) $$,
  '42501',
  'Invite email does not match authenticated user',
  'wrong email cannot accept invite by id'
);

select is(
  (
    select invited_email
    from public.preview_household_invite('open-invite-token')
  ),
  '',
  'open invite preview has no invited email'
);

select lives_ok(
  $$ select public.accept_household_invite('open-invite-token') $$,
  'open invite can be accepted without a matching email'
);

select pg_temp.authenticate_as('33333333-3333-3333-3333-333333333333', 'outsider@example.com');

select throws_ok(
  $$ select public.preview_household_invite('expired-invite-token') $$,
  'P0001',
  'Invite is not available',
  'expired invite cannot be previewed'
);

select throws_ok(
  $$ select public.accept_household_invite('expired-invite-token') $$,
  'P0001',
  'Invite is not available',
  'expired invite cannot be accepted'
);

select throws_ok(
  $$ select public.accept_household_invite('revoked-invite-token') $$,
  'P0001',
  'Invite is not available',
  'revoked invite cannot be accepted'
);

select is(
  (select count(*) from public.list_pending_household_invites()),
  2::bigint,
  'matching invited email can list pending invite reminders'
);

select is(
  (
    select household_name || ':' || owner_email || ':' || inventory_count || ':' || shopping_count
    from public.list_pending_household_invites()
    where invite_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
  ),
  'Kunish Kitchen:owner@example.com:1:1',
  'pending invite reminder includes household overview'
);

select lives_ok(
  $$ select public.accept_household_invite_by_id('dddddddd-dddd-dddd-dddd-dddddddddddd'::uuid) $$,
  'matching invited email can accept invite by id'
);

select is(
  (select count(*) from public.list_pending_household_invites()),
  1::bigint,
  'accepted invite by id is removed from pending reminders'
);

select is(
  (
    select household_name || ':' || owner_email || ':' || inventory_count || ':' || shopping_count
    from public.preview_household_invite('outsider-invite-token')
  ),
  'Kunish Kitchen:owner@example.com:1:1',
  'matching invited email can preview household overview'
);

select lives_ok(
  $$ select public.accept_household_invite('outsider-invite-token') $$,
  'matching invited email can accept invite'
);

select throws_ok(
  $$ select public.accept_household_invite('outsider-invite-token') $$,
  'P0001',
  'Invite is not available',
  'accepted invite cannot be replayed'
);

select is(
  (
    select count(*)
    from public.household_members
    where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and user_id = '33333333-3333-3333-3333-333333333333'
      and role = 'member'
  ),
  1::bigint,
  'accepted user becomes household member'
);

select is(
  (select count(*) from public.households where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  1::bigint,
  'accepted user can read household'
);

-- === New RPC tests for household management enhancement ===

-- Test: anon cannot execute new RPCs
select ok(
  not has_function_privilege('anon', 'public.remove_household_member(uuid, uuid)', 'execute'),
  'anon cannot execute remove_household_member rpc'
);

select ok(
  not has_function_privilege('anon', 'public.leave_household(uuid)', 'execute'),
  'anon cannot execute leave_household rpc'
);

select ok(
  not has_function_privilege('anon', 'public.revoke_household_invite(uuid)', 'execute'),
  'anon cannot execute revoke_household_invite rpc'
);

select ok(
  not has_function_privilege('anon', 'public.list_owner_pending_invites(uuid)', 'execute'),
  'anon cannot execute list_owner_pending_invites rpc'
);

select ok(
  not has_function_privilege('anon', 'public.dissolve_household(uuid)', 'execute'),
  'anon cannot execute dissolve_household rpc'
);

-- Test: owner can remove a member (outsider was added as member earlier)
select pg_temp.authenticate_as('11111111-1111-1111-1111-111111111111', 'owner@example.com');

select lives_ok(
  $$ select public.remove_household_member('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, '33333333-3333-3333-3333-333333333333'::uuid) $$,
  'owner can remove a member'
);

select is(
  (
    select count(*)
    from public.household_members
    where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      and user_id = '33333333-3333-3333-3333-333333333333'
  ),
  0::bigint,
  'removed member is no longer in household'
);

-- Test: owner cannot remove self
select throws_ok(
  $$ select public.remove_household_member('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, '11111111-1111-1111-1111-111111111111'::uuid) $$,
  'P0001',
  'Cannot remove yourself',
  'owner cannot remove self'
);

-- Test: member cannot remove another member (fails owner authorization)
select pg_temp.authenticate_as('22222222-2222-2222-2222-222222222222', 'member@example.com');

select throws_ok(
  $$ select public.remove_household_member('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, '11111111-1111-1111-1111-111111111111'::uuid) $$,
  '42501',
  'Not authorized',
  'member cannot remove another member'
);

-- Test: owner can list pending invites and revoke
select pg_temp.authenticate_as('11111111-1111-1111-1111-111111111111', 'owner@example.com');

-- Insert a fresh pending invite for testing revoke
insert into public.household_invites (
  id,
  household_id,
  email,
  token_hash,
  expires_at,
  created_by
)
values (
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'newinvite@example.com',
  'revoke-test-token',
  now() + interval '7 days',
  '11111111-1111-1111-1111-111111111111'
);

select is(
  (select count(*) from public.list_owner_pending_invites('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid)),
  1::bigint,
  'owner can list pending invites for household'
);

select lives_ok(
  $$ select public.revoke_household_invite('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'::uuid) $$,
  'owner can revoke pending invite'
);

select is(
  (
    select status from public.household_invites
    where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
  ),
  'revoked',
  'revoked invite has revoked status'
);

-- Test: member cannot revoke invite
-- Insert another invite for this test
insert into public.household_invites (
  id,
  household_id,
  email,
  token_hash,
  expires_at,
  created_by
)
values (
  'ffffffff-ffff-ffff-ffff-ffffffffffff',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'another@example.com',
  'member-revoke-test-token',
  now() + interval '7 days',
  '11111111-1111-1111-1111-111111111111'
);

select pg_temp.authenticate_as('22222222-2222-2222-2222-222222222222', 'member@example.com');

select throws_ok(
  $$ select public.revoke_household_invite('ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid) $$,
  '42501',
  'Not authorized or invite not found',
  'member cannot revoke invite'
);

-- Test: member cannot list owner pending invites
select throws_ok(
  $$ select * from public.list_owner_pending_invites('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid) $$,
  '42501',
  'Not authorized',
  'member cannot list owner pending invites'
);

-- === Hardening tests: scoped removal, self-leave, owner_id immutability ===
--
-- Fresh, isolated fixtures so the primary household flow above is untouched.
-- owner2 owns two households (H1, H2); dual is a member of BOTH.

reset role;

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '44444444-4444-4444-4444-444444444444', 'authenticated', 'authenticated', 'owner2@example.com', extensions.crypt('password', extensions.gen_salt('bf')), now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '55555555-5555-5555-5555-555555555555', 'authenticated', 'authenticated', 'dual@example.com', extensions.crypt('password', extensions.gen_salt('bf')), now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '66666666-6666-6666-6666-666666666666', 'authenticated', 'authenticated', 'leaver@example.com', extensions.crypt('password', extensions.gen_salt('bf')), now(), now(), now())
on conflict (id) do nothing;

insert into public.households (id, name, owner_id)
values
  ('b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1', 'House One', '44444444-4444-4444-4444-444444444444'),
  ('b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2', 'House Two', '44444444-4444-4444-4444-444444444444')
on conflict (id) do nothing;

insert into public.household_members (household_id, user_id, role)
values
  ('b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1', '44444444-4444-4444-4444-444444444444', 'owner'),
  ('b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1', '55555555-5555-5555-5555-555555555555', 'member'),
  ('b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1', '66666666-6666-6666-6666-666666666666', 'member'),
  ('b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2', '44444444-4444-4444-4444-444444444444', 'owner'),
  ('b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2', '55555555-5555-5555-5555-555555555555', 'member')
on conflict (household_id, user_id) do nothing;

set local role authenticated;

-- C22: removal is scoped to the named household only.
select pg_temp.authenticate_as('44444444-4444-4444-4444-444444444444', 'owner2@example.com');

select lives_ok(
  $$ select public.remove_household_member('b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1'::uuid, '55555555-5555-5555-5555-555555555555'::uuid) $$,
  'owner can remove a member from a specified household'
);

select is(
  (
    select count(*) from public.household_members
    where household_id = 'b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1'
      and user_id = '55555555-5555-5555-5555-555555555555'
  ),
  0::bigint,
  'member removed from the specified household'
);

select is(
  (
    select count(*) from public.household_members
    where household_id = 'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2'
      and user_id = '55555555-5555-5555-5555-555555555555'
  ),
  1::bigint,
  'member retains membership in the other household'
);

select throws_ok(
  $$ select public.remove_household_member('b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1'::uuid, '55555555-5555-5555-5555-555555555555'::uuid) $$,
  '42501',
  'Not authorized or target is not a member',
  'cannot remove a user who is not a member of the named household'
);

-- C41: owner_id cannot be reassigned via a direct update.
select lives_ok(
  $$ update public.households set name = 'House One Renamed' where id = 'b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1' $$,
  'owner can still update household name'
);

select throws_ok(
  $$ update public.households set owner_id = '55555555-5555-5555-5555-555555555555' where id = 'b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1' $$,
  'P0001',
  'household owner_id cannot be reassigned',
  'owner cannot reassign household owner_id'
);

select is(
  (select owner_id from public.households where id = 'b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1'),
  '44444444-4444-4444-4444-444444444444'::uuid,
  'household owner_id is unchanged after blocked reassignment'
);

-- C40: a member can leave via the RPC.
select pg_temp.authenticate_as('55555555-5555-5555-5555-555555555555', 'dual@example.com');

select lives_ok(
  $$ select public.leave_household('b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2'::uuid) $$,
  'member can leave a household'
);

select is(
  (
    select count(*) from public.household_members
    where household_id = 'b2b2b2b2-b2b2-b2b2-b2b2-b2b2b2b2b2b2'
      and user_id = '55555555-5555-5555-5555-555555555555'
  ),
  0::bigint,
  'member who left is no longer in the household'
);

-- C40: the self-delete policy lets a member delete their own membership row.
select pg_temp.authenticate_as('66666666-6666-6666-6666-666666666666', 'leaver@example.com');

select lives_ok(
  $$ delete from public.household_members
     where household_id = 'b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1'
       and user_id = '66666666-6666-6666-6666-666666666666' $$,
  'member can self-delete their membership row'
);

select is(
  (
    select count(*) from public.household_members
    where household_id = 'b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1'
      and user_id = '66666666-6666-6666-6666-666666666666'
  ),
  0::bigint,
  'self-deleted membership row is gone'
);

-- C40: the sole owner cannot leave and orphan the household.
select pg_temp.authenticate_as('44444444-4444-4444-4444-444444444444', 'owner2@example.com');

select throws_ok(
  $$ select public.leave_household('b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1'::uuid) $$,
  'P0001',
  'Sole owner cannot leave; transfer or dissolve the household instead',
  'sole owner cannot leave the household'
);

-- C40: an owner cannot self-delete their owner row either (no matching policy).
select lives_ok(
  $$ delete from public.household_members
     where household_id = 'b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1'
       and user_id = '44444444-4444-4444-4444-444444444444' $$,
  'owner self-delete affects no rows (no policy permits it)'
);

select is(
  (
    select count(*) from public.household_members
    where household_id = 'b1b1b1b1-b1b1-b1b1-b1b1-b1b1b1b1b1b1'
      and user_id = '44444444-4444-4444-4444-444444444444'
      and role = 'owner'
  ),
  1::bigint,
  'owner row survives a blocked self-delete'
);

-- Restore the member session for the remaining primary-household teardown.
select pg_temp.authenticate_as('22222222-2222-2222-2222-222222222222', 'member@example.com');

-- Test: member cannot dissolve a household
select throws_ok(
  $$ select public.dissolve_household('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid) $$,
  '42501',
  'Not authorized or household not found',
  'member cannot dissolve household'
);

-- Test: owner can dissolve a household and cascade shared data
select pg_temp.authenticate_as('11111111-1111-1111-1111-111111111111', 'owner@example.com');

select lives_ok(
  $$ select public.dissolve_household('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid) $$,
  'owner can dissolve household'
);

reset role;

select is(
  (select count(*) from public.households where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0::bigint,
  'dissolved household is deleted'
);

select is(
  (select count(*) from public.household_members where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0::bigint,
  'dissolved household members are deleted'
);

select is(
  (select count(*) from public.household_invites where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0::bigint,
  'dissolved household invites are deleted'
);

select is(
  (select count(*) from public.inventory_items where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0::bigint,
  'dissolved household inventory is deleted'
);

select is(
  (select count(*) from public.shopping_items where household_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  0::bigint,
  'dissolved household shopping list is deleted'
);

select * from finish();

rollback;
