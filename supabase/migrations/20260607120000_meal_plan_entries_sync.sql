-- Weekly meal-plan entries: household-scoped, realtime-synced.
--
-- Mirrors public.custom_recipes exactly: an opaque jsonb `payload`
-- (date, recipeId, recipeName, recipeImageUrl, servings, done) plus the standard
-- sync columns. Optimistic-concurrency conflict detection reuses the
-- server-authoritative `version` bump trigger (app_private.bump_row_version).
--
-- NOTE: public.sync_events is not written by the meal-plan sync path (the client
-- pushes directly to the entity table), so its entity_type check constraint is
-- intentionally left unchanged. Extend it in a follow-up only if sync_events
-- starts recording meal-plan operations.

create table public.meal_plan_entries (
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

-- Supports the initial full pull and realtime diffing (household_id + updated_at),
-- matching the other content tables.
create index meal_plan_entries_household_updated_idx
  on public.meal_plan_entries (household_id, updated_at);

grant select, insert, update, delete on public.meal_plan_entries to authenticated;

alter table public.meal_plan_entries enable row level security;

create policy "meal_plan_entries_member_all" on public.meal_plan_entries
  for all to authenticated
  using (app_private.is_household_member(household_id))
  with check (app_private.is_household_member(household_id));

-- Make `version` server-authoritative (only ever +1 per update), same as the
-- other synced tables — defends the client's conditional-write conflict guard.
drop trigger if exists meal_plan_entries_bump_version on public.meal_plan_entries;
create trigger meal_plan_entries_bump_version
  before update on public.meal_plan_entries
  for each row
  execute function app_private.bump_row_version();

-- Add to the realtime publication so household members get live updates
-- (idempotent, same guard pattern as the init migration).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'meal_plan_entries'
    ) then
      execute 'alter publication supabase_realtime add table public.meal_plan_entries';
    end if;
  end if;
end;
$$;
