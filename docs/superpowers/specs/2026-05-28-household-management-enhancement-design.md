# Household Management Enhancement — Design Spec

**Date:** 2026-05-28
**Scope:** Iteration 1 — Member management enhancement
**Approach:** Extend existing `HouseholdSection` in settings (Approach A)

## Overview

Three features to enhance household management:

1. **Remove member** — Owner can remove members from the household
2. **Revoke invite** — Owner can revoke pending invites
3. **Multi-household switching** — User can switch between households they belong to

All changes are scoped to the existing `HouseholdSection` widget in the settings screen, with backend RPC additions and gateway/state extensions.

## Architecture

```
HouseholdSection (UI)
  → HouseholdSessionController (StateNotifier)
    → SupabaseHouseholdGateway
      → Supabase RPC / direct table ops
        → RLS enforcement (owner-only for destructive ops)
```

### Files Changed

| Layer | File | Change |
|---|---|---|
| Backend | New migration | `remove_household_member()` + `revoke_household_invite()` RPCs |
| Gateway | `household_session_controller.dart` | `removeMember()`, `revokeInvite()`, `fetchPendingInvites()`, `switchHousehold()` |
| UI | `household_section.dart` | Household switcher + pending invites section + member dismiss |
| State | `HouseholdSessionController` | `pendingInvites` field, `switchHousehold` action |
| Tests | New + existing test files | Unit + widget tests for all new behavior |

## Feature 1: Remove Member

### UI

- Member list items become `Dismissible` (swipe left to reveal red delete button)
- Only visible to the household owner
- Owner's own row is NOT dismissible (cannot remove self)
- Tapping delete shows `showAppConfirmDialog` with "确定移除 {email}？"
- On confirm, calls `controller.removeMember(householdId, targetUserId)`
- On success, member list refreshes automatically

### Backend — `remove_household_member(target_user_id uuid)`

```sql
CREATE OR REPLACE FUNCTION remove_household_member(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_household_id uuid;
  v_caller_id uuid := auth.uid();
BEGIN
  -- Find the household where caller is owner and target is member
  SELECT hm.household_id INTO v_household_id
  FROM household_members hm
  WHERE hm.user_id = target_user_id
    AND hm.role = 'member'
    AND EXISTS (
      SELECT 1 FROM household_members o
      WHERE o.household_id = hm.household_id
        AND o.user_id = v_caller_id
        AND o.role = 'owner'
    );

  IF v_household_id IS NULL THEN
    RAISE EXCEPTION 'Not authorized or target is not a member';
  END IF;

  -- Prevent self-removal
  IF target_user_id = v_caller_id THEN
    RAISE EXCEPTION 'Cannot remove yourself';
  END IF;

  DELETE FROM household_members
  WHERE household_id = v_household_id AND user_id = target_user_id;
END;
$$;
```

### Gateway

```dart
Future<void> removeMember(String householdId, String targetUserId);
```

Implementation calls the RPC via Supabase client.

### State

`HouseholdSessionController.removeMember()` calls gateway, then refreshes `householdMembers`.

### Edge Cases

- Removed user's next `refreshHouseholds()` returns their remaining households (or empty if none)
- If removed user had the household selected, the app falls back to their next available household or shows the bootstrap/login screen

## Feature 2: Revoke Invite

### UI

- Below the member list, a "待处理邀请" section appears (owner only)
- Each row shows: invited email, expiry date, revoke button (X icon)
- Tapping revoke shows confirm dialog "确定撤销对 {email} 的邀请？"
- On confirm, calls `controller.revokeInvite(inviteId)`
- Section hides when no pending invites exist

### Backend — `revoke_household_invite(invite_id uuid)`

```sql
CREATE OR REPLACE FUNCTION revoke_household_invite(invite_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_household_id uuid;
  v_caller_id uuid := auth.uid();
BEGIN
  SELECT hi.household_id INTO v_household_id
  FROM household_invites hi
  WHERE hi.id = invite_id
    AND hi.status = 'pending'
    AND EXISTS (
      SELECT 1 FROM household_members o
      WHERE o.household_id = hi.household_id
        AND o.user_id = v_caller_id
        AND o.role = 'owner'
    );

  IF v_household_id IS NULL THEN
    RAISE EXCEPTION 'Not authorized or invite not found';
  END IF;

  UPDATE household_invites
  SET status = 'revoked'
  WHERE id = invite_id;
END;
$$;
```

### Backend — `list_pending_household_invites(household_id uuid)`

New RPC to fetch pending invites for a specific household (owner only):

```sql
CREATE OR REPLACE FUNCTION list_pending_household_invites(household_id uuid)
RETURNS TABLE(id uuid, email text, expires_at timestamptz, created_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM household_members o
    WHERE o.household_id = household_id
      AND o.user_id = v_caller_id
      AND o.role = 'owner'
  ) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  RETURN QUERY
  SELECT hi.id, hi.email, hi.expires_at, hi.created_at
  FROM household_invites hi
  WHERE hi.household_id = household_id
    AND hi.status = 'pending'
  ORDER BY hi.created_at DESC;
END;
$$;
```

### Gateway

```dart
Future<List<PendingInvite>> fetchPendingInvites(String householdId);
Future<void> revokeInvite(String inviteId);
```

`PendingInvite` is a lightweight model: `{id, email, expiresAt, createdAt}`.

### State

- `HouseholdSessionController` gains `pendingInvites: List<PendingInvite>` in state
- `createInvite()` auto-refreshes pending invites after success
- `revokeInvite()` calls gateway then refreshes pending invites

## Feature 3: Multi-Household Switching

### UI

- `HouseholdSection` header changes from static household name to a `DropdownButton<String>`
- Dropdown items = all households the user belongs to (from `households` list)
- Selecting a different household calls `controller.switchHousehold(householdId)`
- Current household is highlighted

### State

- `switchHousehold(String householdId)` updates `selectedHouseholdIdProvider`
- This cascades to `inventoryProvider`, `shoppingProvider`, `customRecipeProvider` which all depend on it
- `AuthGateScreen`'s `selectedHouseholdIdProvider` override must be updated to react to the controller's selected household

### Gateway

No new gateway methods needed — `refreshHouseholds()` already returns all households.

### Implementation Detail

`AuthGateScreen` currently overrides `selectedHouseholdIdProvider` with `households.first.id`. This needs to change to:

1. `HouseholdSessionController` tracks `selectedHouseholdId` in its state
2. `AuthGateScreen` reads `selectedHouseholdId` from the controller and uses it for the override
3. `switchHousehold()` updates the controller state, which propagates through the override

## Security

All new RPCs are `SECURITY DEFINER` with explicit owner checks. RLS on base tables remains the final safety net:

- `remove_household_member`: Only owner can call, cannot remove self, target must be a `member` role
- `revoke_household_invite`: Only owner can call, invite must belong to owner's household and be `pending`
- `list_pending_household_invites`: Only owner can call, scoped to owner's household

## Testing

### Unit Tests

- `removeMember` rejects non-owner callers (SQL test)
- `removeMember` rejects self-removal (SQL test)
- `revokeInvite` rejects non-owner callers (SQL test)
- `revokeInvite` rejects non-pending invites (SQL test)
- `HouseholdSessionController.removeMember` refreshes member list
- `HouseholdSessionController.revokeInvite` refreshes pending invites
- `HouseholdSessionController.switchHousehold` updates selected ID

### Widget Tests

- `HouseholdSection` shows dismissible on member rows (owner view)
- `HouseholdSection` hides dismissible on own row
- `HouseholdSection` shows pending invites section when invites exist
- `HouseholdSection` hides pending invites section when empty
- `HouseholdSection` dropdown renders all households
- `HouseholdSection` dropdown selection triggers switch

### SQL RLS Tests

- Extend `family_sync_rls.sql` with assertions for new RPCs

## Out of Scope (Future Iterations)

- Editing household name / preferences
- Invite via system share sheet / QR code
- Sync status UI
- Member role promotion (member → owner)
- Household deletion
