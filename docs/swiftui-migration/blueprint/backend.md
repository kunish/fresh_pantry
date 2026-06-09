# backend-supabase-api (`backend`)

**Effort:** L

## 概述

The remote backend is split between a Supabase Postgres project (auth + family-sharing sync, RLS-enforced) and a tiny Cloudflare Worker (health check + invite deep-link bridge). Supabase holds 9 tables (profiles, households, household_members, household_invites, inventory_items, shopping_items, custom_recipes, meal_plan_entries, sync_events). Family-sharing is multi-tenant by household_id with member/owner roles enforced entirely through RLS policies + SECURITY DEFINER RPCs; cross-device sync uses Supabase Realtime (postgres_changes streams) plus an optimistic-concurrency protocol where the client does conditional UPDATEs gated on a server-authoritative integer `version` that a BEFORE UPDATE trigger forces to OLD.version+1. Auth is email-based 6-digit OTP (verifyOTP), with branded Chinese email templates; invites are SHA-256-hashed bearer tokens delivered via deep links that the Cloudflare Worker (api.fresh-pantry.kunish.eu.org) redirects to com.kunish.freshpantry://invite/<token>. The Swift app must talk to this exact contract: same table names, same RPC names + parameter names, same column↔field encoding, and the same conditional-write/version-merge dance.

## 组件(17)

### supabase/migrations/20260527071301_init_family_sync_schema.sql

_Foundational schema: all 8 initial tables, app_private helper functions, RLS policies, accept_household_invite RPC, realtime publication._

SCHEMAS: creates schema app_private (revoke all from public; grant usage to authenticated). extension pgcrypto in schema extensions.

TABLE public.profiles: id uuid PK references auth.users(id) on delete cascade; email text; display_name text; created_at timestamptz not null default now(); updated_at timestamptz not null default now().

TABLE public.households: id uuid PK default gen_random_uuid(); name text not null; owner_id uuid not null references auth.users(id) on delete cascade; default_storage_area text not null default 'fridge'; category_preferences jsonb not null default '{}'; unit_preferences jsonb not null default '{}'; created_at/updated_at timestamptz not null default now().

TABLE public.household_members: household_id uuid not null references households(id) on delete cascade; user_id uuid not null references auth.users(id) on delete cascade; role text not null check (role in ('owner','member')); joined_at timestamptz not null default now(); PRIMARY KEY (household_id, user_id).

TABLE public.household_invites: id uuid PK default gen_random_uuid(); household_id uuid not null references households on delete cascade; email text not null (later made nullable, see open_household_invites migration); token_hash text not null UNIQUE; status text not null default 'pending' check (status in ('pending','accepted','expired','revoked')); expires_at timestamptz not null; accepted_by uuid references auth.users(id); accepted_at timestamptz; created_by uuid not null references auth.users(id); created_at timestamptz not null default now().

TABLE public.inventory_items: id uuid PK default gen_random_uuid(); household_id uuid not null references households on delete cascade; name text not null; quantity text not null; unit text not null; image_url text not null default ''; freshness_percent numeric not null default 1; state text not null default 'fresh'; expiry_label text; category text; barcode text; storage text not null default 'fridge'; expiry_date timestamptz; added_at timestamptz; shelf_life_days integer; version integer not null default 1; client_id text; client_updated_at timestamptz; created_at/updated_at timestamptz not null default now(); deleted_at timestamptz.

TABLE public.shopping_items: id uuid PK default gen_random_uuid(); household_id uuid not null references households on delete cascade; name text not null; detail text not null default ''; image_url text (nullable); category text not null default '其他'; is_checked boolean not null default false; version integer not null default 1; client_id text; client_updated_at timestamptz; created_at/updated_at default now(); deleted_at timestamptz.

TABLE public.custom_recipes: id uuid PK default gen_random_uuid(); household_id uuid not null references households on delete cascade; payload jsonb not null (opaque recipe blob); version integer not null default 1; client_id text; client_updated_at timestamptz; created_at/updated_at default now(); deleted_at timestamptz.

TABLE public.sync_events (audit/event log, NOT used by current client sync path): id uuid PK; household_id uuid not null references households on delete cascade; entity_type text not null check (entity_type in ('inventory_item','shopping_item','custom_recipe','household_config')); entity_id uuid not null; operation text not null; patch jsonb not null default '{}'; base_version integer; result_version integer; client_id text not null; created_by uuid not null references auth.users(id); created_at timestamptz not null default now().

INDEXES: inventory_items_household_updated_idx (household_id, updated_at); shopping_items_household_updated_idx (household_id, updated_at); custom_recipes_household_updated_idx (household_id, updated_at); sync_events_household_created_idx (household_id, created_at); household_invites_email_status_idx (lower(email), status).

GRANTS: select/insert/update/delete on all 8 tables to authenticated.

HELPER FUNCTIONS (app_private, sql, stable, security definer, search_path=public; execute granted only to authenticated): is_household_member(target_household_id uuid)->bool [exists row in household_members where household_id=target and user_id=auth.uid()]; is_household_owner(target_household_id uuid)->bool [same + role='owner']; is_household_owner_record(target_household_id uuid)->bool [households.owner_id = auth.uid()].

RLS enabled on all 8 tables. POLICIES:
- profiles: select/insert/update self where auth.uid()=id.
- households_select_member: select using is_household_member(id). households_insert_owner: insert with check auth.uid()=owner_id. households_update_owner: update using/with check is_household_owner(id) (HARDENED later to also require owner_id=auth.uid()).
- household_members_select_member: select using is_household_member(household_id). household_members_insert_owner_or_existing_owner: insert with check (is_household_owner(household_id) OR (role='owner' AND user_id=auth.uid() AND is_household_owner_record(household_id))). household_members_delete_owner: delete using is_household_owner(household_id) AND role='member'.
- household_invites_select_owner: select using is_household_owner. household_invites_insert_owner: insert with check is_household_owner AND created_by=auth.uid(). household_invites_update_owner: update using is_household_owner AND status<>'accepted' with check (is_household_owner AND status<>'accepted' AND accepted_by is null AND accepted_at is null).
- inventory_items_member_all / shopping_items_member_all / custom_recipes_member_all: FOR ALL using+with check is_household_member(household_id).
- sync_events_select_member: select using is_household_member. sync_events_insert_member_self: insert with check is_household_member AND created_by=auth.uid().

RPC public.accept_household_invite(invite_token_hash text) returns household_members (plpgsql security definer; execute granted to authenticated only, revoked from public/anon). Logic: require auth.uid() (else raise 28000 'Authentication required'); SELECT invite FOR UPDATE by token_hash; if not found OR status<>'pending' OR expires_at<=now() raise P0001 'Invite is not available'; if current_email (lower auth.jwt()->>'email') is empty OR <> lower(invite.email) raise 42501 'Invite email does not match authenticated user'; INSERT into household_members (household_id, user_id, 'member') ON CONFLICT DO NOTHING; set invite status='accepted', accepted_by, accepted_at=now(); return member row. (This email-match check is later relaxed for open invites — see open_household_invites migration.)

REALTIME: idempotent DO block adds inventory_items, shopping_items, custom_recipes, sync_events to publication supabase_realtime.

### supabase/migrations/20260527093000_add_invite_preview_rpc.sql

_Adds preview_household_invite RPC for showing household stats before accepting._

RPC public.preview_household_invite(invite_token_hash text) RETURNS TABLE(household_id uuid, household_name text, owner_email text, invited_email text, member_count integer, inventory_count integer, shopping_count integer, custom_recipe_count integer, expires_at timestamptz). plpgsql security definer search_path=public; execute granted to authenticated only. Logic: require auth.uid() (28000); SELECT invite by token_hash (no FOR UPDATE); if not found/status<>'pending'/expired raise P0001; if email mismatch raise 42501 (later relaxed for open invites); returns one row joining households h, left join profiles p on owner_id, left join auth.users u on owner_id; owner_email=coalesce(p.email,u.email,''); counts filter deleted_at IS NULL for inventory/shopping/custom_recipe. (Superseded by open_household_invites version that coalesces invited_email to '' and skips email check for null-email invites.)

### supabase/migrations/20260527155353_invite_app_reminders.sql

_Refactors invite acceptance into a shared private record helper; adds accept-by-id and list-pending-reminders RPCs (in-app invite reminders)._

app_private.accept_household_invite_record(target_invite_id uuid, target_invite_token_hash text) RETURNS household_members (security definer; execute REVOKED from public/anon/authenticated — only callable by the wrapper SECURITY DEFINER functions). Selects invite FOR UPDATE where (target_invite_id matches id) OR (target_invite_token_hash matches token_hash); same not-available (P0001) + email-match (42501) checks; inserts member ON CONFLICT DO NOTHING; sets status accepted.

public.accept_household_invite(invite_token_hash text) -> delegates to record helper with (null, token_hash). public.accept_household_invite_by_id(target_invite_id uuid) -> delegates with (id, null). Both security definer, execute granted to authenticated only.

public.list_pending_household_invites() RETURNS TABLE(invite_id uuid, household_id uuid, household_name text, owner_email text, invited_email text, member_count int, inventory_count int, shopping_count int, custom_recipe_count int, expires_at timestamptz). Returns all pending, unexpired invites whose lower(email)=lower(auth.jwt email) for the current user, ordered by created_at asc; counts filter deleted_at IS NULL; requires auth.uid() (28000); returns empty if email is ''. Execute granted to authenticated only.

### supabase/migrations/20260528021558_list_household_members.sql

_Adds list_household_members RPC returning members with resolved emails._

RPC public.list_household_members(target_household_id uuid) RETURNS TABLE(household_id uuid, user_id uuid, role text, email text). plpgsql security definer search_path=public; execute granted to authenticated only. Logic: require auth.uid() (28000); if caller is NOT a member of target household raise 42501 'Household access denied'; returns members left-joined to profiles + auth.users, email=coalesce(p.email,u.email,''); ORDER BY (owner first: case role when 'owner' then 0 else 1 end), lower(email), joined_at.

### supabase/migrations/20260528100000_household_management.sql

_Owner management RPCs: remove member (single-arg, later replaced), revoke invite, list owner pending invites._

public.remove_household_member(target_user_id uuid) [SINGLE-ARG VERSION — DROPPED in harden migration]: owner removes a 'member' (cannot remove self -> P0001 'Cannot remove yourself'); matched an arbitrary household where caller is owner (the bug fixed later). public.revoke_household_invite(target_invite_id uuid) returns void: owner sets a pending invite's status='revoked'; raises 42501 'Not authorized or invite not found' if caller not owner of that invite's household or invite not pending. public.list_owner_pending_invites(target_household_id uuid) RETURNS TABLE(id uuid, email text, expires_at timestamptz, created_at timestamptz): owner-only (42501 'Not authorized' if not owner), returns pending invites ordered created_at desc (later version also filters expires_at>now() and coalesces email to ''). All security definer, execute granted to authenticated only.

### supabase/migrations/20260528113000_open_household_invites.sql

_Makes invites optionally email-less (open bearer links / QR), relaxing email checks across all invite RPCs._

ALTER household_invites ALTER COLUMN email DROP NOT NULL. Redefines app_private.accept_household_invite_record, public.preview_household_invite, public.list_pending_household_invites, public.list_owner_pending_invites. KEY CHANGE: email-match check becomes conditional: `if nullif(trim(invite.email),'') is not null AND (current_email='' OR lower(invite.email)<>current_email) then raise 42501`. So a null/blank-email invite is accepted/previewed by ANY authenticated user (open bearer credential). preview/list now coalesce invited_email to ''. list_pending only surfaces invites WHERE nullif(trim(email),'') is not null AND lower(email)=current_email (open invites do NOT appear in email reminders). list_owner_pending_invites now also filters expires_at>now() and coalesces email to ''.

### supabase/migrations/20260528150020_dissolve_household.sql

_Adds dissolve_household RPC for owners to delete a household and cascade all data._

public.dissolve_household(target_household_id uuid) returns void. security definer search_path=public; execute to authenticated only. Logic: require auth.uid() (28000); verify caller is owner of households row AND has an 'owner' member row for it (else raise 42501 'Not authorized or household not found'); DELETE FROM households WHERE id=target AND owner_id=current_user — relies on ON DELETE CASCADE to remove members, invites, inventory_items, shopping_items, custom_recipes, meal_plan_entries, sync_events.

### supabase/migrations/20260529090000_harden_household_security.sql

_Security hardening: scope member removal to an explicit household, allow members to self-leave, forbid reassigning owner_id._

DROPS public.remove_household_member(uuid). Creates public.remove_household_member(target_household_id uuid, target_user_id uuid) returns void: require auth (28000); cannot remove self (P0001 'Cannot remove yourself'); caller must be owner of target_household_id (42501 'Not authorized'); target must be a 'member' of that household (42501 'Not authorized or target is not a member'); deletes that scoped member row. Execute to authenticated.

POLICY household_members_delete_self: delete using (user_id=auth.uid() AND role<>'owner') — lets a non-owner member self-delete their membership row.

public.leave_household(target_household_id uuid) returns void: require auth; if not a member raise 42501 'Not a member of this household'; if role='owner' AND no OTHER owner exists raise P0001 'Sole owner cannot leave; transfer or dissolve the household instead'; else delete own membership row. Execute to authenticated.

Replaces households_update_owner policy: with check now requires (is_household_owner(id) AND owner_id=auth.uid()) — blocks owner_id reassignment via RLS.

TRIGGER app_private.forbid_household_owner_change() BEFORE UPDATE ON households FOR EACH ROW: if new.owner_id IS DISTINCT FROM old.owner_id raise P0001 'household owner_id cannot be reassigned' (defense in depth, also blocks service-role/SECURITY DEFINER).

U14 note: no code path sets status='expired'; pending-past-expiry invites linger but every read path filters expires_at>now() so they are never surfaced/accepted (intentional gap, no pg_cron).

### supabase/migrations/20260529093000_row_version_bump_trigger.sql

_Makes the optimistic-concurrency version counter server-authoritative via BEFORE UPDATE triggers._

FUNCTION app_private.bump_row_version() returns trigger: new.version := old.version + 1; return new. TRIGGERS (BEFORE UPDATE FOR EACH ROW): inventory_items_bump_version, shopping_items_bump_version, custom_recipes_bump_version (meal_plan_entries added in later migration). Effect: client-supplied version in an UPDATE payload is ALWAYS overridden to OLD.version+1; the counter only ever advances by 1 per update, never set by a client. INSERTs untouched (trigger is UPDATE-only), so new rows keep column default 1. CRITICAL: this does NOT conflict with the client's `.eq('version', baseVersion)` WHERE guard — that matches OLD.version (the pre-update row) while the trigger rewrites NEW.version.

### supabase/migrations/20260601035956_inventory_items_dedupe_unique_index.sql

_Partial unique index collapsing duplicate inventory rows from buggy clients._

CREATE UNIQUE INDEX inventory_items_household_name_added_uniq ON inventory_items (household_id, name, added_at) WHERE deleted_at IS NULL. Rationale: a logical inventory item is uniquely (household_id, name, added_at); old clients re-minted fresh UUIDs on each sync bootstrap. Every inventory insert uses upsert(ignoreDuplicates:true) = ON CONFLICT DO NOTHING, so colliding inserts are silently skipped. Partial on deleted_at IS NULL so tombstoned rows never block a legitimate re-add. SWIFT IMPACT: inserting an inventory row that collides on (household_id, name, added_at) among non-deleted rows is silently ignored — must rely on upsert/ignore-duplicates semantics, not expect an error.

### supabase/migrations/20260607120000_meal_plan_entries_sync.sql

_Adds the meal_plan_entries table mirroring custom_recipes (jsonb payload + sync columns), with RLS, version trigger, and realtime._

TABLE public.meal_plan_entries: id uuid PK default gen_random_uuid(); household_id uuid not null references households on delete cascade; payload jsonb not null (opaque: date, recipeId, recipeName, recipeImageUrl, servings, done); version integer not null default 1; client_id text; client_updated_at timestamptz; created_at/updated_at default now(); deleted_at timestamptz. INDEX meal_plan_entries_household_updated_idx (household_id, updated_at). GRANT select/insert/update/delete to authenticated. RLS enabled. POLICY meal_plan_entries_member_all FOR ALL using+with check is_household_member(household_id). TRIGGER meal_plan_entries_bump_version BEFORE UPDATE using app_private.bump_row_version. Added to supabase_realtime publication (idempotent DO block). NOTE: sync_events.entity_type check constraint intentionally NOT extended for meal-plan (client pushes directly to the table, never writes sync_events).

### supabase/config.toml

_Supabase project config: API exposure, auth/OTP/email settings, rate limits, redirect URLs, email templates._

project_id='monorepo-supabase-family-sync'. [api] schemas=['public','graphql_public']; extra_search_path=['public','extensions']; max_rows=1000. [db] major_version=17. [auth] site_url='com.kunish.freshpantry://signin-callback/'; additional_redirect_urls includes that scheme + localhost:3000 variants; jwt_expiry=3600; enable_refresh_token_rotation=true; refresh_token_reuse_interval=10; enable_signup=true; enable_anonymous_sign_ins=false; minimum_password_length=6. [auth.rate_limit] email_sent=2/hr; token_refresh=150; sign_in_sign_ups=30; token_verifications=30 (per 5-min interval). [auth.email] enable_signup=true; double_confirm_changes=true; enable_confirmations=true; secure_password_change=false; max_frequency='15s'; otp_length=6; otp_expiry=3600 (1 hour). EMAIL TEMPLATES point to supabase/templates/*.html with Chinese subjects: magic_link='你的 Fresh Pantry 登录验证码', confirmation, recovery, email_change, reauthentication, invite='你被邀请加入 Fresh Pantry'. CRITICAL (per comment): login/signup/recovery/email-change/reauth render the 6-digit {{ .Token }} entered in-app via verifyOTP (NOT a magic link) — the magic link's PKCE code reached the app but was never exchanged + QQ-mail prefetch consumed the one-time token. ONLY invite stays link-based. SMTP commented out (uses Supabase default sender unless configured in prod). external Apple/Google OAuth all disabled. [realtime] enabled=true.

### supabase/templates/*.html

_Branded Chinese HTML email templates: 5 OTP-code templates + 1 link-based invite._

magic_link.html, confirmation.html, recovery.html, email_change.html, reauthentication.html each render a large 6-digit code via {{ .Token }} (32px, letter-spaced) with copy '验证码 60 分钟内有效' and brand '🥬 Fresh Pantry' green (#2e7d32). email_change.html also interpolates {{ .NewEmail }}. invite.html is the ONLY link template: a '接受邀请' button linking to {{ .ConfirmationURL }}. SWIFT IMPACT: auth flow must call supabase.auth.verifyOTP(email, token, type:) with the 6-digit code, NOT rely on deep-link magic-link/PKCE exchange. Templates are server-side config (push via supabase config push), not app concern, but dictate the auth UX (code entry screen).

### apps/api/src/index.ts (Cloudflare Worker)

_Stateless edge worker bound to custom domain api.fresh-pantry.kunish.eu.org: health endpoint + invite deep-link bridge. No DB/auth — pure HTTP routing._

Constants: INVITE_TOKEN_PATTERN=/^[A-Za-z0-9_-]{10,160}$/; APP_DEEP_LINK_SCHEME='com.kunish.freshpantry'. Default export {async fetch(request)->Response}. ROUTES:
1. GET|HEAD /health -> 200 JSON {service:'fresh-pantry-api', ok:true, timestamp:ISO8601}; other methods -> 405 with header Allow:'GET, HEAD'.
2. GET|HEAD /invite/<token> (regex ^/invite/([^/]+)$): non-read methods -> 405 Allow:'GET, HEAD'; token is decodeURIComponent'd (malformed percent-encoding -> 400 'Invalid invite token'); if token fails INVITE_TOKEN_PATTERN -> 400 'Invalid invite token'; if Accept header includes 'text/html' -> 200 HTML fallback page with an <a href='com.kunish.freshpantry://invite/<encoded token>'>Open invite</a>; otherwise -> 302 redirect (Response.redirect) to com.kunish.freshpantry://invite/<encodeURIComponent(token)>.
3. Any other path -> 404 'Not found'.
wrangler.jsonc: name='fresh-pantry-api', main='src/index.ts', compatibility_date='2026-05-27', custom_domain route 'api.fresh-pantry.kunish.eu.org'. No env bindings/secrets. SWIFT IMPACT: app generates invite URLs as https://api.fresh-pantry.kunish.eu.org/invite/<token>; opening such a URL (from email/QR/share) lands on this worker which redirects into the app's URL scheme. The app must register URL scheme com.kunish.freshpantry and parse host 'invite' + single path segment as the token.

### CLIENT CONTRACT: table/RPC request shapes (lib/sync/remote_pantry_repository.dart, supabase_sync_gateway.dart, remote_row_codec.dart)

_The exact remote API surface the Swift sync layer must reproduce — table names, RPC names + param names, column↔field mappings, and the conditional-write protocol._

DIRECT TABLE OPS (PostgREST): households (select all; insert {id(uuid v4), name, owner_id, default_storage_area:'fridge'}; update {name} or {category_preferences} eq id); household_members (insert {household_id, user_id, role:'owner'}); household_invites (insert {household_id, email(nullable), token_hash:sha256(token), expires_at:ISO8601 UTC (open/email-less invite=now+24h, email-bound=now+3d), created_by}). Content tables inventory_items/shopping_items/custom_recipes/meal_plan_entries: SELECT eq household_id + isFilter deleted_at null for initial pull; .stream(primaryKey:['id']).eq('household_id', hid) for realtime; upsert(ignoreDuplicates:true) for unsynced local creates.

RPC CALLS (client .rpc(name, params)): list_household_members{target_household_id}; list_pending_household_invites{}; preview_household_invite{invite_token_hash:sha256}; accept_household_invite{invite_token_hash}; accept_household_invite_by_id{target_invite_id}; remove_household_member{target_household_id, target_user_id}; leave_household{target_household_id}; revoke_household_invite{target_invite_id}; dissolve_household{target_household_id}; list_owner_pending_invites{target_household_id}.

INVITE TOKEN: 32-char random from [A-Za-z0-9_-]; token_hash = lowercase hex sha256(utf8(token)); invite URL = '<apiBaseUrl>/invite/<rawToken>'. Token-shape regex ^[A-Za-z0-9_-]{10,160}$. Input parser accepts raw token, http(s)://.../invite/<token>, or com.kunish.freshpantry://invite/<token> (also scheme 'freshpantry').

OPTIMISTIC CONCURRENCY (_pushVersionedRow / _updateRemoteRow): create (baseVersion<=0) -> upsert(ignoreDuplicates:true) with version=1, client_id set. update (baseVersion>0) -> UPDATE row (with version=baseVersion+1 in payload, though trigger overrides it) .eq('household_id',hid).eq('id',id).eq('version', baseVersion).select(); if 0 rows returned -> _resolveContendedWrite: re-fetch current row, if null recreate via upsert(ignoreDuplicates), else mergeRemotePatch (client-wins on conflict, reports via FlutterError), write with version=remoteVersion+1 gated on .eq('version', remoteVersion); retry up to 3 times (_maxConflictRetries=3) then throw. Soft delete = UPDATE set deleted_at (same versioned path). shopping toggleChecked = UPDATE set is_checked (versioned). Every write also sets client_id and client_updated_at=operation.createdAt ISO8601.

COLUMN↔DOMAIN MAPPING (remote_row_codec): inventory columns name,quantity,unit, image_url(default ''), freshness_percent(numeric->double default 1.0), state(default 'fresh'), expiry_label, category, barcode, storage(default 'fridge'), expiry_date, added_at, shelf_life_days(int), version->remoteVersion, client_updated_at, deleted_at. shopping columns name, detail(default ''), image_url, category(default '其他'), is_checked(default false), version, client_updated_at, deleted_at. custom_recipes/meal_plan_entries: ALL domain fields live inside jsonb `payload`; only id, version(->remoteVersion), client_updated_at, deleted_at are real columns; decode spreads payload then overlays id/remoteVersion/clientUpdatedAt/deletedAt; encode wraps the whole domain map as payload. id is written on encode ONLY when it is a valid UUID (else DB default fills it); version for upsert is clamped to >=1 (never 0).

### DTOs: household_models.dart

_Client decode shapes for table rows and RPC table results — the JSON keys Swift Decodable must match._

Household: id, name, owner_id, default_storage_area(default 'fridge'), category_preferences(jsonb map). HouseholdMember (from list_household_members): household_id, user_id, role(default 'member'), email. HouseholdInvitePreview (from preview_household_invite / list_pending_household_invites): invite_id(may be absent->''), household_id, household_name, owner_email, invited_email, member_count, inventory_count, shopping_count, custom_recipe_count, expires_at(parseable ISO8601 or null). OwnerPendingInvite (from list_owner_pending_invites): id, email, expires_at, created_at.

### supabase/tests/family_sync_rls.sql + apps/api/test/index.test.ts

_pgTAP RLS/RPC behavior spec (82 assertions) + Worker route spec — authoritative behavior reference for parity testing._

pgTAP confirms: inserted inventory keeps version 1; UPDATE bumps to OLD.version+1 even when client sends a stale/lower version; member can read shared data + list members; non-member denied (counts=0, inserts raise 42501 'new row violates row-level security policy'); wrong-email cannot preview/accept email-bound invite (42501); open (null-email) invite previewable (invited_email='') and acceptable by any authed user; expired/revoked invites raise P0001; accepted invite cannot be replayed (P0001); owner can remove member but not self (P0001); member cannot remove/revoke (42501); removal is scoped to the named household (multi-household owner); owner_id reassignment blocked (P0001 'household owner_id cannot be reassigned'); member can leave, sole owner cannot (P0001); owner can dissolve and cascade members/invites/inventory/shopping; anon has NO execute on any RPC. Worker test confirms 200 health JSON, 302 redirect to deep link for valid token, HTML fallback for Accept text/html, 400 for malformed/percent-bad tokens, 405 for POST.

## 外部集成

- Supabase Auth — email 6-digit OTP login/signup via verifyOTP (NOT magic link / PKCE). otp_length=6, otp_expiry=3600s. site_url & redirect allow com.kunish.freshpantry://signin-callback/. JWT (auth.jwt()->>'email' and auth.uid()) drives all RLS + RPC email-match logic. Swift: Supabase Swift SDK auth.signInWithOTP(email:) then auth.verifyOTP(email:token:type:.email).
- Supabase Postgres (PostgREST + RLS) — 9 tables, multi-tenant by household_id. Config via String.fromEnvironment SUPABASE_URL + SUPABASE_PUBLISHABLE_KEY (compile-time dart-define; Swift equivalent: build config / xcconfig). API base host is the project's *.supabase.co (not the Cloudflare domain).
- Supabase Realtime — postgres_changes streams on inventory_items, shopping_items, custom_recipes, meal_plan_entries (publication supabase_realtime), filtered by household_id, primary key id. Used for live cross-device family sync. Swift: RealtimeChannelV2 postgresChange listeners or .stream.
- Supabase RPC (SECURITY DEFINER functions) — 10 callable RPCs for household/invite management (names+params listed in components). All execute-granted to authenticated only, revoked from anon.
- Cloudflare Worker — api.fresh-pantry.kunish.eu.org. GET /health (liveness) and GET /invite/<token> (302 redirect or HTML fallback into the app URL scheme). The ONLY place the app's invite URLs resolve; not an auth/data API. apiBaseUrl env: FRESH_PANTRY_API_BASE_URL default https://api.fresh-pantry.kunish.eu.org.
- Invite deep links / Universal-link-style bridge — URL scheme com.kunish.freshpantry, host 'invite', single path segment = raw token. App must register this scheme and route to invite-acceptance flow (preview then accept). Also handles signin-callback host.

## Swift 映射

Implement a RemoteBackend layer using the Supabase Swift SDK (supabase-swift): SupabaseClient configured with the project URL + publishable (anon) key from an xcconfig/build setting, plus an apiBaseURL constant for the Cloudflare invite domain. AUTH: an actor/@Observable AuthService wrapping client.auth — signInWithOTP(email:) for login/signup, verifyOTP(email:token:type:.email) for the 6-digit code (build a code-entry SwiftUI screen; do NOT implement magic-link/PKCE deep-link exchange). Register URL scheme com.kunish.freshpantry; handle host 'invite' (token) and 'signin-callback'. REMOTE REPO: a Swift actor RemotePantryRepository mirroring the Dart abstract class — methods for loadHouseholds/createHousehold/createInvite/loadHouseholdMembers/loadPendingInvites/previewInvite/acceptInvite/acceptInviteById/removeMember/revokeInvite/dissolveHousehold/leaveHousehold/fetchOwnerPendingInvites/updateHouseholdName/updateCategoryPreferences plus per-table load/upsert/watch. Use client.from(\"table\").select()/.insert()/.update()/.upsert(onConflict… ignoreDuplicates) and client.rpc(\"name\", params:) with the EXACT param names listed. Define Codable structs matching the column JSON (snake_case via CodingKeys or .convertFromSnakeCase): InventoryRow, ShoppingRow, CustomRecipeRow/MealPlanRow (with a `payload` field that is the opaque domain JSON), HouseholdRow, HouseholdMember, HouseholdInvitePreview, OwnerPendingInvite. SYNC ENGINE: a SyncCoordinator actor implementing the optimistic-concurrency protocol — local rows carry an Int `version`; creates use upsert(ignoreDuplicates:true) with version=1; updates do a conditional UPDATE .eq household_id/.eq id/.eq version(baseVersion).select() and on empty result re-fetch + client-wins merge + retry (max 3) gated on the actual remote version. Realtime via client.realtimeV2 channels (postgresChange on each content table filtered by household_id). INVITE TOKENS: generate 32-char [A-Za-z0-9_-] via SystemRandomNumberGenerator; token_hash = SHA256 hex (CryptoKit Insecure? no — use SHA256) of UTF8(token); store the hash, share the raw token in the https://<apiBaseURL>/invite/<token> URL. Background sync (push outbox + realtime reconnect) via BGTaskScheduler. SwiftData @Model types hold the local mirror with the same fields + a sync version/clientUpdatedAt/deletedAt for the outbox.

## 迁移注意

PARITY-CRITICAL INVARIANTS: (1) `version` is server-authoritative — the BEFORE UPDATE trigger forces version=OLD.version+1 and IGNORES whatever value the client sends. Conditional writes MUST gate on .eq('version', baseVersion) which matches the OLD row, NOT trust the value coming back. Swift must replicate the conditional-UPDATE + re-fetch-merge-retry loop exactly or it will livelock or lose updates. (2) Soft deletes only: rows are tombstoned via deleted_at (never hard-deleted by the client); all initial pulls filter deleted_at IS NULL; realtime streams do NOT filter deleted_at so the client must drop tombstoned rows after a delete event. (3) The (household_id, name, added_at) partial unique index silently swallows duplicate inventory inserts (ON CONFLICT DO NOTHING via ignoreDuplicates) — never expect an insert error; always preserve the original added_at when re-syncing an item. (4) Invites: email-bound invites require lower(jwt email)==lower(invite.email) to preview/accept (42501 on mismatch); null/blank-email 'open' invites skip that check and are acceptable by any authenticated user — token possession IS the credential, so treat open-invite URLs as bearer secrets (24h expiry vs 3d for email-bound). token_hash is SHA256 hex of the raw token; the raw token never leaves the device except inside the shared URL. (5) custom_recipes & meal_plan_entries store the ENTIRE domain object inside jsonb `payload`; only id/version/client_updated_at/deleted_at are columns — Swift encode must wrap the domain map as payload and decode must spread it back. (6) sync_events table exists but the current client never writes it (direct table pushes); do not wire it up. (7) id is written only when a valid UUID — otherwise rely on the DB default (gen_random_uuid). (8) ERROR CODES the UI keys off: 28000=auth required, P0001=invite unavailable / cannot-remove-self / sole-owner / owner_id-immutable, 42501=email mismatch / not authorized. (9) AUTH IS OTP-CODE not magic-link: the magic_link/confirmation/recovery/email_change/reauth templates all render {{ .Token }}; the original PKCE deep-link flow was abandoned because the code was never exchanged and QQ-mail prefetch consumed one-time tokens — Swift must use verifyOTP. SEQUENCING: createHousehold inserts the households row THEN a household_members owner row (two writes, not atomic — handle partial failure). owner_id can never be reassigned (trigger + RLS) so 'transfer ownership' is not supported; only dissolve or leave.

## 开放问题

- households.unit_preferences (jsonb) column exists in schema but the client Household model only reads category_preferences — is unit_preferences used anywhere, or dead? (no client read found in this subsystem's files).
- SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY are injected via dart-define at build time and not committed; the actual production Supabase project URL/anon key must be sourced from the build pipeline / secrets for the Swift xcconfig (not present in repo).
- sync_events table + its RLS/insert policies are fully built but unused by the current client (meal_plan note confirms direct-table push). Confirm whether the Swift rewrite should also skip it (recommended) or whether a future audit-log is planned.
- No transfer-ownership RPC exists (owner_id is immutable by trigger+RLS); confirm the product intentionally has no ownership-transfer feature, only dissolve/leave.
- Invite 'expired' status is never written (only filtered at read time); confirm Swift should likewise rely on expires_at>now() rather than a status transition.
- Realtime streams are not deleted_at-filtered (only initial pull is) — confirm the intended client behavior is to drop a row locally when a realtime event arrives with deleted_at set (inferred but worth verifying against the local sync coordinator outside this subsystem).
