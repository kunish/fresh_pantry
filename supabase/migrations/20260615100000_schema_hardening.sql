-- Schema hardening: constraint backfills, CHECK enforcement, index and trigger additions.
-- All statements are idempotent: backfills are WHERE-guarded, constraints use
-- DROP IF EXISTS before ADD, indexes use IF NOT EXISTS, trigger uses CREATE OR REPLACE +
-- DROP IF EXISTS.

-- ==============================================================================
-- [08 P1] inventory_items.added_at: backfill NULLs then enforce NOT NULL + default
-- The dedup unique index on (household_id, name, added_at) WHERE deleted_at IS NULL
-- treats NULL != NULL, so two rows with added_at = NULL both satisfy the predicate
-- and bypass the uniqueness guarantee. Backfill and constrain to close the gap.
-- ==============================================================================

-- created_at is NOT NULL DEFAULT now() (confirmed in 20260527071301 line 66).
update public.inventory_items
  set added_at = coalesce(added_at, created_at, now())
  where added_at is null;

alter table public.inventory_items
  alter column added_at set default now();

alter table public.inventory_items
  alter column added_at set not null;

-- ==============================================================================
-- [08 P1] inventory_items.state: backfill unexpected values then add CHECK constraint.
-- Valid raw values from FreshnessState enum in apps/ios/FreshPantry/Domain/Enums.swift:
-- 'fresh', 'expiringSoon', 'urgent', 'expired' (case-sensitive, verified from source).
-- ==============================================================================

update public.inventory_items
  set state = 'fresh'
  where state not in ('fresh', 'expiringSoon', 'urgent', 'expired');

alter table public.inventory_items
  drop constraint if exists inventory_items_state_check;

alter table public.inventory_items
  add constraint inventory_items_state_check
  check (state in ('fresh', 'expiringSoon', 'urgent', 'expired'));

-- ==============================================================================
-- [08 P1] inventory_items.freshness_percent: clamp out-of-range values then constrain.
-- The iOS client treats freshness_percent as a 0..1 fraction; the column has no
-- range guard so client bugs could persist values like -5 or 101.
-- ==============================================================================

update public.inventory_items
  set freshness_percent = least(greatest(freshness_percent, 0), 1)
  where freshness_percent < 0 or freshness_percent > 1;

alter table public.inventory_items
  drop constraint if exists inventory_items_freshness_range;

alter table public.inventory_items
  add constraint inventory_items_freshness_range
  check (freshness_percent >= 0 and freshness_percent <= 1);

-- ==============================================================================
-- [08 P1] sync_events.entity_type: extend stale CHECK to cover all 8 entity types.
-- The original constraint only listed 4; meal_plan_entry, food_log_entry,
-- favorite_recipe, dietary_preference were added in later migrations without
-- updating the constraint, making it misleading and a future write time-bomb.
-- ==============================================================================

alter table public.sync_events
  drop constraint if exists sync_events_entity_type_check;

alter table public.sync_events
  add constraint sync_events_entity_type_check
  check (entity_type in (
    'inventory_item',
    'shopping_item',
    'custom_recipe',
    'household_config',
    'meal_plan_entry',
    'food_log_entry',
    'favorite_recipe',
    'dietary_preference'
  ));

-- ==============================================================================
-- [08 P2] profiles.updated_at: add BEFORE UPDATE trigger so the column
-- auto-refreshes on every row update. Without this, updated_at permanently
-- reflects the creation timestamp, breaking any sync/cache keyed on it.
-- Follows the same app_private trigger-function pattern as bump_row_version
-- (20260529093000); no explicit revoke/grant needed for trigger functions.
-- ==============================================================================

create or replace function app_private.touch_updated_at()
  returns trigger
  language plpgsql
  set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;

create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row
  execute function app_private.touch_updated_at();

-- ==============================================================================
-- [08 P2] household_invites: add index on household_id.
-- RPCs list_owner_pending_invites, preview_household_invite, and
-- list_pending_household_invites all filter by household_id; without an index
-- each call does a full scan of household_invites.
-- ==============================================================================

create index if not exists household_invites_household_idx
  on public.household_invites (household_id);

-- ==============================================================================
-- [09 P1] avatars storage bucket: add file size limit and MIME-type allowlist.
-- The bucket was created without limits (20260611120000), inheriting the global
-- 50 MiB cap and accepting arbitrary MIME types including SVG. Mirror the
-- recipe-images bucket approach (20260613094239).
-- ==============================================================================

update storage.buckets
  set file_size_limit   = 5242880,
      allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
  where id = 'avatars';

-- ==============================================================================
-- SKIPPED: favorite_recipes / dietary_preferences payload uniqueness index.
-- The analysis suggested unique indexes on (payload->>'recipeID', household_id)
-- and (payload->>'keyword', household_id). These are deliberately skipped because:
--   1. The deterministic client-computed UUID primary key already provides
--      last-write-wins convergence for the same logical (household, recipe/keyword).
--   2. The actual payload key is 'recipeID' (capital ID), which is fragile as an
--      index expression — any key rename would silently stop enforcing the index.
--   3. A partial unique index on a jsonb expression adds a write-path constraint
--      that can break ingestion in unexpected ways without clear benefit given (1).
-- SKIPPED: bump_row_version trigger — server-authoritative and correct; no change.
-- ==============================================================================
