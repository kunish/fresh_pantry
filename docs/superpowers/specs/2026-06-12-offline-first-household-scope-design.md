# Offline-first household scope restore — design

Date: 2026-06-12
Status: approved (approach chosen by maintainer)

## Problem

The data layer is already local-first (every feature Store reads SwiftData
before any network), yet a cold launch can show **empty history first, then
data appears after the network round-trip**. Offline launches stay empty
forever.

Root cause: the household scope, not the data.

1. `SyncSession.selectedHouseholdId` starts at `""` on every launch and is
   never persisted (`SyncSession.swift` — only `clientId` is stored).
2. Every Store filters SwiftData by `householdID`; scope `""` returns zero
   rows even though the household's rows sit on disk.
3. The real id only arrives after Keychain restore → `refreshHouseholds()`
   (a Supabase query, `HouseholdSessionStore.swift:110-121`). Offline, that
   never succeeds → the app shows empty despite full local data.
4. Aggravator: `RootView`'s auto-select `.task(id: signedInEmail)` runs once
   at launch with a transient `nil` email and resets the scope to `""`.

## Decision

Persist `selectedHouseholdId` and restore it at init, so launch reads the
household-scoped SwiftData immediately; `refreshHouseholds()` corrects the
scope asynchronously once online.

Rejected alternatives: full offline session snapshot (household list +
members — over-engineered for a self-use app); network-failure-only fallback
(keeps the online empty-flash).

## Changes

1. **`SyncSession`** — persist `selectedHouseholdId` under
   `fresh_pantry.sync.selected_household_id` in the injected `UserDefaults`
   (same suite as `clientId`). `init` restores the persisted value when the
   caller passes the default `""`; an explicit non-empty initial id (tests /
   previews) wins for the instance without writing through — only runtime
   assignments persist (`didSet`), so seeded test containers can't pollute
   `.standard`.

2. **`RootView` auto-select task** — re-key on
   `hasResolvedSession # signedInEmail` and bail while the session is
   unresolved, so the launch-transient `nil` email no longer clobbers the
   restored scope. A *resolved* signed-out state still resets + persists
   `""` (sign-out and expired-session launches keep today's semantics:
   local-only empty scope).

3. **`RootView` content-sync task** — re-key on
   `hasResolvedSession # signedInEmail # selectedHouseholdId` and only call
   `syncTo(non-empty id)` when signed in. **Data-safety requirement**: the
   restored scope must not start an unauthenticated bulk pull —
   `HouseholdMergePolicy.merge` keeps only `remoteVersion <= 0` local rows,
   so an anon RLS-empty pull would wipe all synced local rows.

## Invariants preserved

- Single root-owned `SyncSession` (parity #5) — unchanged.
- Sign-out resets scope to `""` (now also persisted), local edits stop
  enqueueing against the old household.
- Removal from / switch of household: `refreshHouseholds` →
  `pickSelected` writes the session → `didSet` persists the correction.
- Local-only mode (`backend == nil`): `hasResolvedSession` starts `true`,
  `householdContentSync` is nil — gates are no-ops.

## Testing

- `SyncSessionTests`: persistence round-trip across instances sharing a
  suite; explicit initial id wins over persisted; assignment persists;
  reset-to-`""` persists; fresh suite still defaults to `""`.
- RootView task gating is SwiftUI glue; covered by the existing live-sync
  debug hooks rather than unit tests.
