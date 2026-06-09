import Foundation
import Testing
@testable import FreshPantry

/// Household DTO decode parity: full-payload decode, the exact `fromJson`
/// defaults when keys are absent, snake_case -> camelCase mapping, and the
/// asymmetric date handling (tolerant preview date vs. required owner-invite
/// dates) that keeps Supabase response decoding aligned with the Flutter app.
struct HouseholdModelsTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func expectThrows<T: Decodable>(_ type: T.Type, _ json: String) {
        #expect(throws: (any Error).self) {
            try self.decode(type, json)
        }
    }

    // MARK: Household

    @Test func householdDecodesAllKeys() throws {
        let json = #"""
        {
          "id": "hh_1",
          "name": "我的家",
          "owner_id": "user_1",
          "default_storage_area": "freezer",
          "category_preferences": {"肉类海鲜": {"sort": 1}}
        }
        """#
        let household = try decode(Household.self, json)
        #expect(household.id == "hh_1")
        #expect(household.name == "我的家")
        #expect(household.ownerId == "user_1")
        #expect(household.defaultStorageArea == "freezer")
        #expect(
            household.categoryPreferences
                == ["肉类海鲜": .object(["sort": .int(1)])]
        )
    }

    @Test func householdAppliesDefaultsWhenKeysAbsent() throws {
        let household = try decode(Household.self, "{}")
        #expect(household.id == "")
        #expect(household.name == "")
        #expect(household.ownerId == "")
        #expect(household.defaultStorageArea == "fridge")
        #expect(household.categoryPreferences.isEmpty)
    }

    @Test func householdCategoryPreferencesTolerateNonObject() throws {
        // Dart guards with `is Map`; a non-object value falls back to `{}`.
        let household = try decode(Household.self, #"{"category_preferences": "nope"}"#)
        #expect(household.categoryPreferences.isEmpty)
    }

    // MARK: HouseholdMember

    @Test func memberDecodesAllKeys() throws {
        let json = #"""
        {"household_id": "hh_1", "user_id": "user_2", "role": "owner", "email": "a@b.com"}
        """#
        let member = try decode(HouseholdMember.self, json)
        #expect(member.householdId == "hh_1")
        #expect(member.userId == "user_2")
        #expect(member.role == "owner")
        #expect(member.email == "a@b.com")
    }

    @Test func memberAppliesDefaultsWhenKeysAbsent() throws {
        let member = try decode(HouseholdMember.self, "{}")
        #expect(member.householdId == "")
        #expect(member.userId == "")
        #expect(member.role == "member")
        #expect(member.email == "")
    }

    // MARK: HouseholdInvitePreview

    @Test func invitePreviewDecodesAllKeys() throws {
        let json = #"""
        {
          "invite_id": "inv_1",
          "household_id": "hh_1",
          "household_name": "我的家",
          "owner_email": "owner@x.com",
          "invited_email": "guest@x.com",
          "member_count": 3,
          "inventory_count": 12,
          "shopping_count": 4,
          "custom_recipe_count": 2,
          "expires_at": "2026-06-20T08:00:00.000Z"
        }
        """#
        let preview = try decode(HouseholdInvitePreview.self, json)
        #expect(preview.inviteId == "inv_1")
        #expect(preview.householdId == "hh_1")
        #expect(preview.householdName == "我的家")
        #expect(preview.ownerEmail == "owner@x.com")
        #expect(preview.invitedEmail == "guest@x.com")
        #expect(preview.memberCount == 3)
        #expect(preview.inventoryCount == 12)
        #expect(preview.shoppingCount == 4)
        #expect(preview.customRecipeCount == 2)
        #expect(preview.expiresAt == JSONDate.parse("2026-06-20T08:00:00.000Z"))
    }

    @Test func invitePreviewAppliesDefaultsWhenKeysAbsent() throws {
        // Preview shape from `preview_household_invite` omits invite_id.
        let preview = try decode(HouseholdInvitePreview.self, "{}")
        #expect(preview.inviteId == "")
        #expect(preview.householdId == "")
        #expect(preview.householdName == "")
        #expect(preview.ownerEmail == "")
        #expect(preview.invitedEmail == "")
        #expect(preview.memberCount == 0)
        #expect(preview.inventoryCount == 0)
        #expect(preview.shoppingCount == 0)
        #expect(preview.customRecipeCount == 0)
        #expect(preview.expiresAt == nil)
    }

    @Test func invitePreviewExpiresAtTolerantOfNull() throws {
        let preview = try decode(HouseholdInvitePreview.self, #"{"expires_at": null}"#)
        #expect(preview.expiresAt == nil)
    }

    @Test func invitePreviewExpiresAtTolerantOfBlankAndGarbage() throws {
        // Mirrors `DateTime.tryParse("")` and `DateTime.tryParse("nope")` -> null.
        #expect(try decode(HouseholdInvitePreview.self, #"{"expires_at": ""}"#).expiresAt == nil)
        #expect(
            try decode(HouseholdInvitePreview.self, #"{"expires_at": "not-a-date"}"#)
                .expiresAt == nil
        )
    }

    @Test func invitePreviewCountsTolerateDoubleEncoding() throws {
        // Dart `(num?)?.toInt()` truncates a JSON double to Int.
        let preview = try decode(
            HouseholdInvitePreview.self,
            #"{"member_count": 3.0, "inventory_count": 12.9}"#
        )
        #expect(preview.memberCount == 3)
        #expect(preview.inventoryCount == 12)
    }

    // MARK: OwnerPendingInvite

    @Test func ownerInviteDecodesAllKeys() throws {
        let json = #"""
        {
          "id": "inv_9",
          "email": "guest@x.com",
          "expires_at": "2026-06-20T08:00:00.000Z",
          "created_at": "2026-06-13T08:00:00.000Z"
        }
        """#
        let invite = try decode(OwnerPendingInvite.self, json)
        #expect(invite.id == "inv_9")
        #expect(invite.email == "guest@x.com")
        #expect(invite.expiresAt == JSONDate.parse("2026-06-20T08:00:00.000Z"))
        #expect(invite.createdAt == JSONDate.parse("2026-06-13T08:00:00.000Z"))
    }

    @Test func ownerInviteAppliesStringDefaultsButKeepsDates() throws {
        // id / email null-coalesce; dates are still required and present here.
        let json = #"""
        {"expires_at": "2026-06-20T08:00:00.000Z", "created_at": "2026-06-13T08:00:00.000Z"}
        """#
        let invite = try decode(OwnerPendingInvite.self, json)
        #expect(invite.id == "")
        #expect(invite.email == "")
        #expect(invite.expiresAt == JSONDate.parse("2026-06-20T08:00:00.000Z"))
    }

    @Test func ownerInviteThrowsWhenExpiresAtMissing() {
        expectThrows(
            OwnerPendingInvite.self,
            #"{"id": "x", "email": "g@x.com", "created_at": "2026-06-13T08:00:00.000Z"}"#
        )
    }

    @Test func ownerInviteThrowsWhenCreatedAtMissing() {
        expectThrows(
            OwnerPendingInvite.self,
            #"{"id": "x", "email": "g@x.com", "expires_at": "2026-06-20T08:00:00.000Z"}"#
        )
    }

    @Test func ownerInviteThrowsWhenDateBlankOrUnparseable() {
        // Dart `DateTime.parse("")` / `DateTime.parse("nope")` throw.
        expectThrows(
            OwnerPendingInvite.self,
            #"{"expires_at": "", "created_at": "2026-06-13T08:00:00.000Z"}"#
        )
        expectThrows(
            OwnerPendingInvite.self,
            #"{"expires_at": "nope", "created_at": "2026-06-13T08:00:00.000Z"}"#
        )
    }
}
