-- Makes the optimistic-concurrency `version` counter server-authoritative.
--
-- The Flutter client performs conditional writes
-- (UPDATE ... WHERE version = baseVersion, re-fetch + merge on conflict) and
-- sends its own intended `version` (baseVersion + 1) in the update payload.
-- A stale, malicious, or service-role caller could otherwise write a lower or
-- arbitrary `version`, defeating the conflict detection (audit C4/C43).
--
-- This BEFORE UPDATE trigger ignores the client-supplied value and always sets
-- `version = OLD.version + 1`, so the counter only ever moves forward by one per
-- update regardless of what the caller sends. It does not conflict with the
-- client's `.eq('version', baseVersion)` guard: that WHERE clause matches
-- OLD.version (the pre-update row), while the trigger rewrites NEW.version.
--
-- INSERTs are untouched (trigger is UPDATE-only); new rows keep the column
-- default of 1.

-- Defense in depth on every update path (RLS, SECURITY DEFINER, service role):
-- a row version can only ever be advanced by exactly one, never set by a client.
create or replace function app_private.bump_row_version()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.version := old.version + 1;
  return new;
end;
$$;

drop trigger if exists inventory_items_bump_version on public.inventory_items;
create trigger inventory_items_bump_version
  before update on public.inventory_items
  for each row
  execute function app_private.bump_row_version();

drop trigger if exists shopping_items_bump_version on public.shopping_items;
create trigger shopping_items_bump_version
  before update on public.shopping_items
  for each row
  execute function app_private.bump_row_version();

drop trigger if exists custom_recipes_bump_version on public.custom_recipes;
create trigger custom_recipes_bump_version
  before update on public.custom_recipes
  for each row
  execute function app_private.bump_row_version();
