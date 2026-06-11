# 个人信息（头像 / 名称 / 昵称）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让用户设置头像 / 名称 / 昵称，在家庭成员列表中显示，并在新用户登录后强制填写显示名。

**Architecture:** Profile 是 per-user（主键即 `auth.users.id`，无 household），与现有 household-scoped 的 content 同步本质不同，因此走一套**轻量直写**同步（本地乐观更新 + pending 重试），不接 `HouseholdContentSyncCoordinator`。头像存 Supabase Storage 的 public `avatars` 桶；成员显示名/头像随已有的 `list_household_members` RPC（`security definer`，已 `left join profiles`）一并返回，无需放宽 `profiles` 的 select RLS。

**Tech Stack:** SwiftUI + SwiftData（`@Model` / `@ModelActor`）+ `@Observable @MainActor` stores + supabase-swift 2.47.0（Postgrest / Storage / Auth）。测试：Swift Testing（`@Test` / `#expect`）+ pgTAP。

**Spec:** `docs/superpowers/specs/2026-06-11-personal-profile-design.md`

---

## File Structure

**新建**
- `supabase/migrations/20260611120000_profile_personal_info.sql` — profiles 加列 + 扩展 `list_household_members` RPC + `avatars` Storage 桶 + storage RLS。
- `apps/ios/FreshPantry/Sync/Household/ProfileModels.swift` — `UserProfile` DTO（Codable/Sendable）。
- `apps/ios/FreshPantry/Persistence/ProfileRecord.swift` — SwiftData `@Model`（单行本地缓存 + `pendingUpload`）。
- `apps/ios/FreshPantry/Persistence/Repositories/ProfileRepository.swift` — `@ModelActor`：单行本地读写 + `LocalProfile` 快照。
- `apps/ios/FreshPantry/Features/Settings/ProfileRemote.swift` — `ProfileRemote` 协议（store 的远端 seam，可注入 fake）。
- `apps/ios/FreshPantry/Features/Settings/ProfileStore.swift` — `@Observable @MainActor`：load / save / pending 重试 / `needsProfileSetup`。
- `apps/ios/FreshPantry/Features/Settings/ProfileEditView.swift` — 编辑/onboarding 共用的头像+名称+昵称表单。
- `apps/ios/FreshPantryTests/Persistence/ProfileRepositoryTests.swift`
- `apps/ios/FreshPantryTests/ProfileStoreTests.swift`
- `apps/ios/FreshPantryTests/Sync/ProfileModelsTests.swift`

**修改**
- `apps/ios/FreshPantry/Sync/RemotePantryRepository.swift` — 加 profile load/upsert/avatar 方法 + `ProfileRemote` 一致性扩展。
- `apps/ios/FreshPantry/Sync/Household/HouseholdModels.swift` — `HouseholdMember` 加 `displayName` / `nickname` / `avatarPath` + `resolvedName`。
- `apps/ios/FreshPantry/Persistence/ModelContainerFactory.swift` — 注册 `ProfileRecord`。
- `apps/ios/FreshPantry/App/AppDependencies.swift` — 注入 `profileRepository` + `profileStore`。
- `apps/ios/FreshPantry/Features/Household/HouseholdView.swift` — `memberRow` 显示头像 + `resolvedName`。
- `apps/ios/FreshPantry/Features/Settings/SettingsView.swift` — 顶部「个人资料」入口。
- `apps/ios/FreshPantry/App/RootView.swift` — 登录后 onboarding gate（`.fullScreenCover`）。
- `supabase/tests/family_sync_rls.sql` — `list_household_members` 返回 `display_name` 断言。

**关键类型契约（跨 task 必须一致）**
- `UserProfile`：`id, email, displayName, nickname, avatarPath`（全部 `String`，空串表示未设置）。
- `LocalProfile`：`{ profile: UserProfile, pendingUpload: Bool }`（`Sendable` 快照，跨 actor 边界传递，绝不传 `@Model`）。
- `ProfileRemote`（协议）：
  - `func loadMyProfile() async throws -> UserProfile?`
  - `func upsertMyProfile(displayName: String, nickname: String, avatarPath: String) async throws`
  - `func uploadAvatar(_ data: Data) async throws -> String`（返回 storage path）
  - `nonisolated func avatarPublicURL(path: String) -> URL?`
- 头像 path：`{userId}/{uuid}.jpg`（每次换图新文件名，URL 随之变天然破缓存；旧文件不清理 — 自用 app 量小，可接受）。

---

## Task 1: Supabase migration — profiles 列 + RPC + Storage 桶

**Files:**
- Create: `supabase/migrations/20260611120000_profile_personal_info.sql`

- [ ] **Step 1: 写 migration**

```sql
-- Personal profile: nickname + avatar; surface them through the members RPC; an
-- avatars Storage bucket (public read, owner-only write). profiles stays
-- user-scoped (PK = auth.users.id) — no version/client columns, single writer.

alter table public.profiles
  add column if not exists nickname text,
  add column if not exists avatar_path text;

-- Extend list_household_members to carry profile display fields. It is
-- security definer and already left-joins profiles, so members see each other's
-- display_name/nickname/avatar_path WITHOUT widening the profiles select RLS.
create or replace function public.list_household_members(target_household_id uuid)
returns table (
  household_id uuid,
  user_id uuid,
  role text,
  email text,
  display_name text,
  nickname text,
  avatar_path text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if not exists (
    select 1
    from public.household_members hm
    where hm.household_id = target_household_id
      and hm.user_id = current_user_id
  ) then
    raise exception 'Household access denied' using errcode = '42501';
  end if;

  return query
  select
    hm.household_id,
    hm.user_id,
    hm.role,
    coalesce(p.email, u.email, ''),
    coalesce(p.display_name, ''),
    coalesce(p.nickname, ''),
    coalesce(p.avatar_path, '')
  from public.household_members hm
  left join public.profiles p on p.id = hm.user_id
  left join auth.users u on u.id = hm.user_id
  where hm.household_id = target_household_id
  order by
    case hm.role when 'owner' then 0 else 1 end,
    lower(coalesce(p.email, u.email, '')),
    hm.joined_at;
end;
$$;

revoke all on function public.list_household_members(uuid) from public;
revoke all on function public.list_household_members(uuid) from anon;
grant execute on function public.list_household_members(uuid) to authenticated;

-- Avatars bucket: public read (display via getPublicURL), owner-only write.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- A user may only write objects under their own {auth.uid()}/ prefix.
create policy "avatars_insert_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "avatars_update_own" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "avatars_delete_own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
```

- [ ] **Step 2: 应用 migration 到本地/远端 Supabase**

Run（本地 stack）: `supabase db reset` — 或对远端：通过 Supabase MCP `apply_migration`。
Expected: 无报错；`profiles` 多出 `nickname` / `avatar_path` 两列，`avatars` 桶存在。

验证（任一连接）:
Run: `supabase db diff` 或在 SQL 控制台跑 `select column_name from information_schema.columns where table_name='profiles';`
Expected: 包含 `nickname` 和 `avatar_path`。

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260611120000_profile_personal_info.sql
git commit -m "feat(supabase): profiles 加 nickname/avatar_path + members RPC 带出 + avatars Storage 桶"
```

---

## Task 2: RLS 测试 — members RPC 返回 display_name

**Files:**
- Modify: `supabase/tests/family_sync_rls.sql`

- [ ] **Step 1: 更新 plan 计数**

把开头的 `select plan(82);` 改为 `select plan(83);`（本 task 新增 1 个断言）。

- [ ] **Step 2: 给 owner 插入一条 profile fixture**

在文件顶部的 fixtures 区（`insert into public.households ...` 之后）追加：

```sql
insert into public.profiles (id, email, display_name, nickname)
values ('11111111-1111-1111-1111-111111111111', 'owner@example.com', '户主大人', 'Boss')
on conflict (id) do update
  set display_name = excluded.display_name,
      nickname = excluded.nickname;
```

- [ ] **Step 3: 加断言 — member 可读 owner 的 display_name**

在现有 `'member can list household members with emails'` 断言（`select is(... string_agg(email || ':' || role ...)`）之后追加：

```sql
select is(
  (
    select display_name
    from public.list_household_members('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
    where user_id = '11111111-1111-1111-1111-111111111111'
  ),
  '户主大人',
  'members RPC surfaces the owner display_name'
);
```

- [ ] **Step 4: 跑 pgTAP**

Run: `supabase test db`（或 `pg_prove` 按项目既有方式）
Expected: 全部通过，计数 83/83，新断言 `members RPC surfaces the owner display_name` 通过。

- [ ] **Step 5: Commit**

```bash
git add supabase/tests/family_sync_rls.sql
git commit -m "test(supabase): list_household_members 返回 display_name 断言"
```

---

## Task 3: `UserProfile` DTO

**Files:**
- Create: `apps/ios/FreshPantry/Sync/Household/ProfileModels.swift`
- Test: `apps/ios/FreshPantryTests/Sync/ProfileModelsTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import Foundation
import Testing
@testable import FreshPantry

struct ProfileModelsTests {
    @Test func decodesSnakeCaseRowWithDefaults() throws {
        let json = """
        {"id":"u1","email":"a@b.com","display_name":"小明","nickname":"明明","avatar_path":"u1/x.jpg"}
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(UserProfile.self, from: json)
        #expect(p.id == "u1")
        #expect(p.displayName == "小明")
        #expect(p.nickname == "明明")
        #expect(p.avatarPath == "u1/x.jpg")
    }

    @Test func missingOptionalFieldsDefaultToEmpty() throws {
        let json = """
        {"id":"u2","email":"c@d.com","display_name":"阿花"}
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(UserProfile.self, from: json)
        #expect(p.nickname == "")
        #expect(p.avatarPath == "")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme FreshPantry -only-testing:FreshPantryTests/ProfileModelsTests` （或 Xcode 内运行该测试文件）
Expected: 编译失败 / `UserProfile` 未定义。

- [ ] **Step 3: 实现 `UserProfile`**

```swift
import Foundation

/// The user's personal profile (`profiles` table). Per-user, NOT household-scoped.
/// Decodes the Supabase row's snake_case keys lenient-with-defaults, matching the
/// household DTOs' tolerant style: an absent optional field is "" (未设置).
struct UserProfile: Equatable, Sendable, Codable {
    var id: String
    var email: String
    var displayName: String
    var nickname: String
    var avatarPath: String

    private enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case nickname
        case avatarPath = "avatar_path"
    }

    init(
        id: String = "",
        email: String = "",
        displayName: String = "",
        nickname: String = "",
        avatarPath: String = ""
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.nickname = nickname
        self.avatarPath = avatarPath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: c.decodeLenientIfPresent(String.self, forKey: .id) ?? "",
            email: c.decodeLenientIfPresent(String.self, forKey: .email) ?? "",
            displayName: c.decodeLenientIfPresent(String.self, forKey: .displayName) ?? "",
            nickname: c.decodeLenientIfPresent(String.self, forKey: .nickname) ?? "",
            avatarPath: c.decodeLenientIfPresent(String.self, forKey: .avatarPath) ?? ""
        )
    }
}
```

> `decodeLenientIfPresent` 是项目既有的 `KeyedDecodingContainer` 扩展（`HouseholdMember` 等都用它）；直接复用。

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme FreshPantry -only-testing:FreshPantryTests/ProfileModelsTests`
Expected: 2 个测试 PASS。

- [ ] **Step 5: Commit**

```bash
git add apps/ios/FreshPantry/Sync/Household/ProfileModels.swift apps/ios/FreshPantryTests/Sync/ProfileModelsTests.swift
git commit -m "feat(ios): UserProfile DTO（snake_case lenient 解码）"
```

---

## Task 4: `ProfileRecord` + `ProfileRepository`

**Files:**
- Create: `apps/ios/FreshPantry/Persistence/ProfileRecord.swift`
- Create: `apps/ios/FreshPantry/Persistence/Repositories/ProfileRepository.swift`
- Modify: `apps/ios/FreshPantry/Persistence/ModelContainerFactory.swift:12-22`
- Test: `apps/ios/FreshPantryTests/Persistence/ProfileRepositoryTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import Foundation
import SwiftData
import Testing
@testable import FreshPantry

struct ProfileRepositoryTests {
    private func container() throws -> ModelContainer { try ModelContainerFactory.makeInMemory() }

    @Test func loadNilWhenEmpty() async throws {
        let repo = ProfileRepository(modelContainer: try container())
        #expect(try await repo.load() == nil)
    }

    @Test func saveThenLoadRoundTrip() async throws {
        let repo = ProfileRepository(modelContainer: try container())
        let profile = UserProfile(id: "u1", email: "a@b.com", displayName: "小明", nickname: "明", avatarPath: "u1/x.jpg")
        try await repo.save(profile, pendingUpload: true)
        let loaded = try await repo.load()
        #expect(loaded?.profile == profile)
        #expect(loaded?.pendingUpload == true)
    }

    @Test func saveIsSingleRow() async throws {
        let repo = ProfileRepository(modelContainer: try container())
        try await repo.save(UserProfile(id: "u1", displayName: "A"), pendingUpload: false)
        try await repo.save(UserProfile(id: "u1", displayName: "B"), pendingUpload: false)
        let loaded = try await repo.load()
        #expect(loaded?.profile.displayName == "B")
        #expect(try await repo.count() == 1)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme FreshPantry -only-testing:FreshPantryTests/ProfileRepositoryTests`
Expected: 编译失败 / `ProfileRecord` / `ProfileRepository` 未定义。

- [ ] **Step 3: 实现 `ProfileRecord`**

```swift
import Foundation
import SwiftData

/// SwiftData row caching the CURRENT user's profile (single row). Drives instant
/// display on launch and powers the pending-upload retry when a save couldn't
/// reach the backend. NOT a per-member store — only "me" lives here.
@Model
final class ProfileRecord {
    var id: String = ""
    var email: String = ""
    var displayName: String = ""
    var nickname: String = ""
    var avatarPath: String = ""
    /// True when the local edit hasn't been confirmed pushed to the backend yet.
    var pendingUpload: Bool = false

    init(profile: UserProfile, pendingUpload: Bool) {
        id = profile.id
        email = profile.email
        displayName = profile.displayName
        nickname = profile.nickname
        avatarPath = profile.avatarPath
        self.pendingUpload = pendingUpload
    }

    func profile() -> UserProfile {
        UserProfile(id: id, email: email, displayName: displayName, nickname: nickname, avatarPath: avatarPath)
    }
}
```

- [ ] **Step 4: 实现 `ProfileRepository`**

```swift
import Foundation
import SwiftData

/// Sendable snapshot of the cached profile (never hand a `@Model` across the
/// actor boundary).
struct LocalProfile: Sendable, Equatable {
    let profile: UserProfile
    let pendingUpload: Bool
}

/// Single-row local store for the current user's profile. `save` replaces the row
/// (clear-then-insert) so there is never more than one.
@ModelActor
actor ProfileRepository {
    func load() throws -> LocalProfile? {
        guard let row = try modelContext.fetch(FetchDescriptor<ProfileRecord>()).first else { return nil }
        return LocalProfile(profile: row.profile(), pendingUpload: row.pendingUpload)
    }

    func save(_ profile: UserProfile, pendingUpload: Bool) throws {
        for row in try modelContext.fetch(FetchDescriptor<ProfileRecord>()) {
            modelContext.delete(row)
        }
        modelContext.insert(ProfileRecord(profile: profile, pendingUpload: pendingUpload))
        try modelContext.save()
    }

    /// Test/diagnostic helper: number of cached rows (must stay ≤ 1).
    func count() throws -> Int {
        try modelContext.fetch(FetchDescriptor<ProfileRecord>()).count
    }
}
```

- [ ] **Step 5: 注册到 `ModelContainerFactory`**

把 `ModelContainerFactory.models` 数组（`apps/ios/FreshPantry/Persistence/ModelContainerFactory.swift:12-22`）中加入 `ProfileRecord.self`：

```swift
    static let models: [any PersistentModel.Type] = [
        InventoryItemRecord.self,
        ShoppingItemRecord.self,
        CustomRecipeRecord.self,
        MealPlanRecord.self,
        FoodLogRecord.self,
        ProfileRecord.self,
        SyncOutboxRecord.self,
        AddHistoryRecord.self,
        FoodDetailsCacheRecord.self,
        BarcodeMemoryRecord.self,
    ]
```

- [ ] **Step 6: 跑测试确认通过**

Run: `xcodebuild test -scheme FreshPantry -only-testing:FreshPantryTests/ProfileRepositoryTests`
Expected: 3 个测试 PASS。

- [ ] **Step 7: Commit**

```bash
git add apps/ios/FreshPantry/Persistence/ProfileRecord.swift \
        apps/ios/FreshPantry/Persistence/Repositories/ProfileRepository.swift \
        apps/ios/FreshPantry/Persistence/ModelContainerFactory.swift \
        apps/ios/FreshPantryTests/Persistence/ProfileRepositoryTests.swift
git commit -m "feat(ios): ProfileRecord + ProfileRepository（单行本地缓存 + pending）"
```

---

## Task 5: `HouseholdMember` 加 profile 字段

**Files:**
- Modify: `apps/ios/FreshPantry/Sync/Household/HouseholdModels.swift:64-98`
- Test: `apps/ios/FreshPantryTests/Household/HouseholdSessionStoreTests.swift`（追加一个解码测试，或新建 `HouseholdMemberTests.swift`）

- [ ] **Step 1: 写失败测试**

新建 `apps/ios/FreshPantryTests/Household/HouseholdMemberTests.swift`：

```swift
import Foundation
import Testing
@testable import FreshPantry

struct HouseholdMemberTests {
    @Test func decodesProfileFieldsFromRPCRow() throws {
        let json = """
        {"household_id":"h1","user_id":"u1","role":"owner","email":"a@b.com",
         "display_name":"小明","nickname":"明明","avatar_path":"u1/x.jpg"}
        """.data(using: .utf8)!
        let m = try JSONDecoder().decode(HouseholdMember.self, from: json)
        #expect(m.displayName == "小明")
        #expect(m.nickname == "明明")
        #expect(m.avatarPath == "u1/x.jpg")
    }

    @Test func resolvedNamePrefersNicknameThenDisplayNameThenEmail() {
        #expect(HouseholdMember(email: "a@b.com", displayName: "小明", nickname: "明明").resolvedName == "明明")
        #expect(HouseholdMember(email: "a@b.com", displayName: "小明").resolvedName == "小明")
        #expect(HouseholdMember(email: "a@b.com").resolvedName == "a@b.com")
        #expect(HouseholdMember().resolvedName == "成员")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme FreshPantry -only-testing:FreshPantryTests/HouseholdMemberTests`
Expected: 编译失败 / `displayName` 等成员不存在。

- [ ] **Step 3: 扩展 `HouseholdMember`**

把 `HouseholdModels.swift:64-98` 的 `HouseholdMember` 整体替换为：

```swift
/// A member row from the `list_household_members` RPC. `role` defaults to
/// `member`; the profile fields default to "" (未设置) to match the Flutter
/// factory's tolerant decode.
struct HouseholdMember: Equatable, Sendable, Codable {
    var householdId: String
    var userId: String
    var role: String
    var email: String
    var displayName: String
    var nickname: String
    var avatarPath: String

    private enum CodingKeys: String, CodingKey {
        case householdId = "household_id"
        case userId = "user_id"
        case role
        case email
        case displayName = "display_name"
        case nickname
        case avatarPath = "avatar_path"
    }

    init(
        householdId: String = "",
        userId: String = "",
        role: String = "member",
        email: String = "",
        displayName: String = "",
        nickname: String = "",
        avatarPath: String = ""
    ) {
        self.householdId = householdId
        self.userId = userId
        self.role = role
        self.email = email
        self.displayName = displayName
        self.nickname = nickname
        self.avatarPath = avatarPath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            householdId: c.decodeLenientIfPresent(String.self, forKey: .householdId) ?? "",
            userId: c.decodeLenientIfPresent(String.self, forKey: .userId) ?? "",
            role: c.decodeLenientIfPresent(String.self, forKey: .role) ?? "member",
            email: c.decodeLenientIfPresent(String.self, forKey: .email) ?? "",
            displayName: c.decodeLenientIfPresent(String.self, forKey: .displayName) ?? "",
            nickname: c.decodeLenientIfPresent(String.self, forKey: .nickname) ?? "",
            avatarPath: c.decodeLenientIfPresent(String.self, forKey: .avatarPath) ?? ""
        )
    }

    /// Display label: nickname → display_name → email → "成员".
    var resolvedName: String {
        if !nickname.isEmpty { return nickname }
        if !displayName.isEmpty { return displayName }
        if !email.isEmpty { return email }
        return "成员"
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme FreshPantry -only-testing:FreshPantryTests/HouseholdMemberTests`
Expected: 2 个测试 PASS。

- [ ] **Step 5: Commit**

```bash
git add apps/ios/FreshPantry/Sync/Household/HouseholdModels.swift apps/ios/FreshPantryTests/Household/HouseholdMemberTests.swift
git commit -m "feat(ios): HouseholdMember 加 display_name/nickname/avatar_path + resolvedName"
```

---

## Task 6: `RemotePantryRepository` 加 profile + avatar 方法

**Files:**
- Create: `apps/ios/FreshPantry/Features/Settings/ProfileRemote.swift`
- Modify: `apps/ios/FreshPantry/Sync/RemotePantryRepository.swift`

> 远端调用无单测（需真实 Supabase）；本 task 以「编译通过 + 协议一致」为验证，行为由 Task 11 的手动验证覆盖。

- [ ] **Step 1: 定义 `ProfileRemote` 协议**

写 `apps/ios/FreshPantry/Features/Settings/ProfileRemote.swift`：

```swift
import Foundation

/// The profile store's remote seam. `RemotePantryRepository` conforms in
/// production; tests inject a fake to exercise the optimistic-save / pending
/// paths without a live backend. Kept narrow on purpose (interface segregation).
protocol ProfileRemote: Sendable {
    func loadMyProfile() async throws -> UserProfile?
    func upsertMyProfile(displayName: String, nickname: String, avatarPath: String) async throws
    func uploadAvatar(_ data: Data) async throws -> String
    /// Public URL for a stored avatar path, or nil for an empty path. Synchronous
    /// (no actor hop) so SwiftUI rows can build the URL inline.
    nonisolated func avatarPublicURL(path: String) -> URL?
}
```

- [ ] **Step 2: 在 `RemotePantryRepository` 实现这些方法**

在 `RemotePantryRepository.swift` 的 `// MARK: - Household / invite RPCs` 区块之前（紧接 `updateCategoryPreferences` 之后）插入：

```swift
    // MARK: - Profile (user-scoped, single writer)

    /// `from('profiles').select().eq('id', myId)` → my `UserProfile`, or nil when
    /// the row doesn't exist yet (first sign-in before onboarding saves it).
    func loadMyProfile() async throws -> UserProfile? {
        let userId = try requireUserId(action: "load profile")
        let rows: [UserProfile] = try await client
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .execute()
            .value
        return rows.first
    }

    /// Upserts the signed-in user's profile row. id + email come from the session
    /// (never the caller) so a client can only ever write its OWN profile; empty
    /// nickname/avatar are stored as null. `updated_at` is set explicitly so an
    /// update (not just insert) bumps it.
    func upsertMyProfile(displayName: String, nickname: String, avatarPath: String) async throws {
        let userId = try requireUserId(action: "update profile")
        let email = client.auth.currentUser?.email ?? ""
        let row: [String: AnyJSON] = [
            "id": .string(userId),
            "email": .string(email),
            "display_name": .string(displayName),
            "nickname": nickname.isEmpty ? .null : .string(nickname),
            "avatar_path": avatarPath.isEmpty ? .null : .string(avatarPath),
            "updated_at": .string(JSONDate.iso8601(Date())),
        ]
        try await client.from("profiles").upsert(row).execute()
    }

    /// Uploads avatar bytes to `avatars/{userId}/{uuid}.jpg` and returns the path.
    /// A fresh uuid filename per upload means the public URL changes on every
    /// change (natural cache-bust); old objects are left in place (small, A-mode).
    func uploadAvatar(_ data: Data) async throws -> String {
        let userId = try requireUserId(action: "upload avatar")
        let path = "\(userId)/\(UUID().uuidString.lowercased()).jpg"
        try await client.storage
            .from("avatars")
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
        return path
    }

    /// Public URL for an avatar path. `nonisolated` so a SwiftUI row builds it
    /// inline; reads only the actor's immutable `Sendable` client.
    nonisolated func avatarPublicURL(path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        return try? client.storage.from("avatars").getPublicURL(path: path)
    }
```

- [ ] **Step 3: 声明协议一致性**

在 `RemotePantryRepository.swift` 文件末尾（`actor` 闭合大括号之后）追加：

```swift
extension RemotePantryRepository: ProfileRemote {}
```

> `requireUserId` / `JSONDate.iso8601` / `AnyJSON` / `import Supabase`（含 `FileOptions`、`storage`）都已在本文件可用。

- [ ] **Step 4: 编译验证**

Run: `xcodebuild build -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED（`RemotePantryRepository` 满足 `ProfileRemote`，`avatarPublicURL` 的 `nonisolated` 访问 `client` 不报并发错误）。

- [ ] **Step 5: Commit**

```bash
git add apps/ios/FreshPantry/Features/Settings/ProfileRemote.swift apps/ios/FreshPantry/Sync/RemotePantryRepository.swift
git commit -m "feat(ios): RemotePantryRepository 加 profile load/upsert + avatar 上传/URL（ProfileRemote）"
```

---

## Task 7: `ProfileStore`

**Files:**
- Create: `apps/ios/FreshPantry/Features/Settings/ProfileStore.swift`
- Test: `apps/ios/FreshPantryTests/ProfileStoreTests.swift`

- [ ] **Step 1: 写失败测试（含 fake remote）**

```swift
import Foundation
import Testing
@testable import FreshPantry

@MainActor
struct ProfileStoreTests {
    /// In-memory fake of the remote seam. `failUpsert` forces the push to throw so
    /// the pending-retention path can be asserted.
    final class FakeProfileRemote: ProfileRemote, @unchecked Sendable {
        var stored: UserProfile?
        var uploadedCount = 0
        var failUpsert = false

        func loadMyProfile() async throws -> UserProfile? { stored }
        func upsertMyProfile(displayName: String, nickname: String, avatarPath: String) async throws {
            if failUpsert { throw RemotePantryError.notSignedIn(action: "test") }
            stored = UserProfile(id: "me", email: "me@x.com", displayName: displayName, nickname: nickname, avatarPath: avatarPath)
        }
        func uploadAvatar(_ data: Data) async throws -> String { uploadedCount += 1; return "me/new.jpg" }
        nonisolated func avatarPublicURL(path: String) -> URL? {
            path.isEmpty ? nil : URL(string: "https://cdn/\(path)")
        }
    }

    private func makeStore(remote: FakeProfileRemote?) throws -> ProfileStore {
        let container = try ModelContainerFactory.makeInMemory()
        return ProfileStore(remote: remote, local: ProfileRepository(modelContainer: container))
    }

    @Test func loadPullsRemoteIntoState() async throws {
        let remote = FakeProfileRemote()
        remote.stored = UserProfile(id: "me", email: "me@x.com", displayName: "小明", nickname: "明")
        let store = try makeStore(remote: remote)
        await store.load(signedIn: true)
        #expect(store.displayName == "小明")
        #expect(store.nickname == "明")
        #expect(store.hasLoaded)
    }

    @Test func needsProfileSetupWhenSignedInAndNoDisplayName() async throws {
        let store = try makeStore(remote: FakeProfileRemote())   // remote.stored == nil
        await store.load(signedIn: true)
        #expect(store.needsProfileSetup)
    }

    @Test func savedDisplayNameClearsNeedsSetup() async throws {
        let remote = FakeProfileRemote()
        let store = try makeStore(remote: remote)
        await store.load(signedIn: true)
        await store.save(displayName: "阿花", nickname: "", newAvatar: nil)
        #expect(!store.needsProfileSetup)
        #expect(store.errorMessage == nil)
        #expect(!store.hasPendingUpload)
        #expect(remote.stored?.displayName == "阿花")
    }

    @Test func failedSaveRetainsPendingAndSurfacesError() async throws {
        let remote = FakeProfileRemote()
        remote.failUpsert = true
        let store = try makeStore(remote: remote)
        await store.load(signedIn: true)
        await store.save(displayName: "阿花", nickname: "", newAvatar: nil)
        #expect(store.hasPendingUpload)
        #expect(store.errorMessage != nil)
        // Optimistic local state still reflects the edit.
        #expect(store.displayName == "阿花")
    }

    @Test func uploadsAvatarBeforeUpsert() async throws {
        let remote = FakeProfileRemote()
        let store = try makeStore(remote: remote)
        await store.load(signedIn: true)
        await store.save(displayName: "阿花", nickname: "", newAvatar: Data([0xFF]))
        #expect(remote.uploadedCount == 1)
        #expect(store.avatarPath == "me/new.jpg")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme FreshPantry -only-testing:FreshPantryTests/ProfileStoreTests`
Expected: 编译失败 / `ProfileStore` 未定义。

- [ ] **Step 3: 实现 `ProfileStore`**

```swift
import Foundation

/// Drives the profile-edit + onboarding UI. Local-first optimistic writes: an
/// edit updates local state immediately, then pushes to the backend; a push
/// failure RETAINS a pending flag and surfaces the error (never silent). Single
/// writer (only "me"), so there is no version/merge — just last-write + retry.
@Observable
@MainActor
final class ProfileStore {
    private(set) var displayName = ""
    private(set) var nickname = ""
    private(set) var avatarPath = ""
    private(set) var email = ""
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var hasPendingUpload = false
    private(set) var hasLoaded = false

    private let remote: ProfileRemote?
    private let local: ProfileRepository
    /// Whether the user is signed in — gates `needsProfileSetup` (a signed-out /
    /// local-only user is never asked to fill a profile). Set by `load`.
    private var isSignedIn = false

    init(remote: ProfileRemote?, local: ProfileRepository) {
        self.remote = remote
        self.local = local
    }

    /// True when we should force the onboarding profile step: loaded, signed in,
    /// and no display name yet.
    var needsProfileSetup: Bool {
        hasLoaded && isSignedIn && displayName.trimmed.isEmpty
    }

    /// Public URL of the current avatar (nil when none / no backend).
    var avatarURL: URL? { remote?.avatarPublicURL(path: avatarPath) }

    /// Loads local cache first (instant), then refreshes from the backend. A
    /// remote failure keeps the local snapshot (offline-tolerant).
    func load(signedIn: Bool) async {
        isSignedIn = signedIn
        if let cached = try? await local.load() {
            apply(cached.profile)
            hasPendingUpload = cached.pendingUpload
        }
        if signedIn, let remote {
            do {
                if let fetched = try await remote.loadMyProfile() {
                    apply(fetched)
                    try? await local.save(fetched, pendingUpload: false)
                    hasPendingUpload = false
                }
            } catch {
                // Keep the local snapshot; surfacing here would be noisy on launch.
            }
        }
        hasLoaded = true
        // A still-pending edit from a previous session: try to flush it now.
        if hasPendingUpload { await retryPendingUpload() }
    }

    /// Optimistic save. Uploads a new avatar first (if any), then upserts the row.
    /// On success clears pending; on failure retains pending + sets errorMessage.
    func save(displayName newName: String, nickname newNick: String, newAvatar: Data?) async {
        isSaving = true
        errorMessage = nil
        let trimmedName = newName.trimmed
        let trimmedNick = newNick.trimmed

        // Optimistic local state immediately.
        displayName = trimmedName
        nickname = trimmedNick

        do {
            var path = avatarPath
            if let data = newAvatar, let remote {
                path = try await remote.uploadAvatar(data)
            }
            avatarPath = path
            let profile = UserProfile(id: "", email: email, displayName: trimmedName, nickname: trimmedNick, avatarPath: path)

            guard let remote else {
                // No backend (local-only): persist locally, mark pending so it
                // flushes once a backend/household is wired.
                try? await local.save(profile, pendingUpload: true)
                hasPendingUpload = true
                isSaving = false
                return
            }

            try await remote.upsertMyProfile(displayName: trimmedName, nickname: trimmedNick, avatarPath: path)
            try? await local.save(profile, pendingUpload: false)
            hasPendingUpload = false
        } catch {
            // Retain the edit + pending flag so the foreground/online retry resends.
            let profile = UserProfile(id: "", email: email, displayName: trimmedName, nickname: trimmedNick, avatarPath: avatarPath)
            try? await local.save(profile, pendingUpload: true)
            hasPendingUpload = true
            errorMessage = "保存失败,已在本地保留,稍后会自动重试。"
        }
        isSaving = false
    }

    /// Re-pushes a pending local edit. Called on load and can be called on
    /// foreground / reconnect. No-op when nothing is pending or no backend.
    func retryPendingUpload() async {
        guard hasPendingUpload, let remote else { return }
        do {
            try await remote.upsertMyProfile(displayName: displayName, nickname: nickname, avatarPath: avatarPath)
            let profile = UserProfile(id: "", email: email, displayName: displayName, nickname: nickname, avatarPath: avatarPath)
            try? await local.save(profile, pendingUpload: false)
            hasPendingUpload = false
            errorMessage = nil
        } catch {
            // Still pending; leave the flag set for the next trigger.
        }
    }

    private func apply(_ profile: UserProfile) {
        displayName = profile.displayName
        nickname = profile.nickname
        avatarPath = profile.avatarPath
        if !profile.email.isEmpty { email = profile.email }
    }
}
```

> `String.trimmed` 是项目既有扩展（`HouseholdView` / `RemotePantryRepository` 都在用）。

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild test -scheme FreshPantry -only-testing:FreshPantryTests/ProfileStoreTests`
Expected: 5 个测试全部 PASS。

- [ ] **Step 5: Commit**

```bash
git add apps/ios/FreshPantry/Features/Settings/ProfileStore.swift apps/ios/FreshPantryTests/ProfileStoreTests.swift
git commit -m "feat(ios): ProfileStore（乐观保存 + 失败保留 pending + needsProfileSetup）"
```

---

## Task 8: 注入 `AppDependencies`

**Files:**
- Modify: `apps/ios/FreshPantry/App/AppDependencies.swift`

> 纯接线，无独立单测；以编译通过验证。

- [ ] **Step 1: 声明属性**

在 `AppDependencies` 的存储属性区（紧接 `let foodLogRepository: FoodLogRepository` 之后）加：

```swift
    /// Single-row local cache of the current user's profile (avatar/name/nickname).
    let profileRepository: ProfileRepository
    /// Drives the profile-edit screen + the登录后 onboarding profile gate. Shared
    /// so Settings and the root gate read the SAME state.
    let profileStore: ProfileStore
```

- [ ] **Step 2: 构造 `profileRepository`**

在 `init` 中 `self.foodLogRepository = FoodLogRepository(modelContainer: modelContainer)` 之后加：

```swift
        self.profileRepository = ProfileRepository(modelContainer: modelContainer)
```

- [ ] **Step 3: 构造 `profileStore`（remote 可空降级）**

`profileStore` 需要 `remotePantryRepository`，而后者在 `if let client { ... } else { ... }` 两个分支里分别赋值。为避免依赖赋值顺序，在 `init` 的**最后一行**（两个分支都跑完、`self.householdContentSync` 等已就绪之后）加：

```swift
        // Built last so it can read the (optional) remote repository regardless of
        // which backend branch ran. `RemotePantryRepository` conforms to
        // `ProfileRemote`; local-only mode passes nil (store degrades to local).
        self.profileStore = ProfileStore(
            remote: self.remotePantryRepository,
            local: self.profileRepository
        )
```

> Swift 要求所有 stored property 在 init 结束前赋值；`profileStore` 放最后满足这一点，且能读到已设好的 `remotePantryRepository`。

- [ ] **Step 4: 编译验证**

Run: `xcodebuild build -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED。

- [ ] **Step 5: Commit**

```bash
git add apps/ios/FreshPantry/App/AppDependencies.swift
git commit -m "feat(ios): AppDependencies 注入 profileRepository + profileStore"
```

---

## Task 9: `ProfileEditView`（编辑 + onboarding 共用）

**Files:**
- Create: `apps/ios/FreshPantry/Features/Settings/ProfileEditView.swift`

> SwiftUI 视图无单测；以编译 + 手动验证（Task 11）为准。

- [ ] **Step 1: 实现视图**

```swift
import PhotosUI
import SwiftUI

/// Profile editor, reused for both Settings (editable, dismissable) and the
/// post-login onboarding gate (`mode == .onboarding`: display name required,
/// not dismissable until saved).
struct ProfileEditView: View {
    enum Mode { case settings, onboarding }

    let store: ProfileStore
    var mode: Mode = .settings

    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var nickname = ""
    @State private var pickerItem: PhotosPickerItem?
    /// Locally-picked avatar bytes (not yet uploaded) for instant preview.
    @State private var pickedAvatar: Data?

    private var canSave: Bool { !displayName.trimmed.isEmpty && !store.isSaving }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FkSpacing.xl) {
                    avatarPicker
                    FkCard {
                        VStack(alignment: .leading, spacing: FkSpacing.lg) {
                            FkFormField(label: "名称") {
                                FkTextFieldPill(text: $displayName, placeholder: "在家庭里显示的名字")
                            }
                            FkFormField(label: "昵称(可选)") {
                                FkTextFieldPill(text: $nickname, placeholder: "留空则使用名称")
                            }
                            if mode == .onboarding {
                                Text("名称会显示在家庭成员列表里,先填一个吧。")
                                    .font(.fkBodySmall)
                                    .foregroundStyle(Color.fkOnSurfaceVariant)
                            }
                        }
                    }
                    if let errorMessage = store.errorMessage {
                        errorBanner(errorMessage)
                    }
                    saveButton
                }
                .padding(FkSpacing.lg)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(Color.fkSurface)
            .navigationTitle(mode == .onboarding ? "完善个人信息" : "个人资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if mode == .settings {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                    }
                }
            }
            .tint(.fkPrimary)
            .interactiveDismissDisabled(mode == .onboarding)
        }
        .task {
            displayName = store.displayName
            nickname = store.nickname
        }
        .onChange(of: pickerItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    pickedAvatar = compressed(data)
                }
            }
        }
    }

    // MARK: Avatar

    private var avatarPicker: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            ZStack {
                if let pickedAvatar, let ui = UIImage(data: pickedAvatar) {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else if let url = store.avatarURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        avatarFallback
                    }
                } else {
                    avatarFallback
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.fkOutlineVariant))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.fkOnPrimary)
                    .padding(6)
                    .background(Circle().fill(Color.fkPrimary))
            }
        }
        .buttonStyle(.fkPressable)
    }

    private var avatarFallback: some View {
        ZStack {
            Color.fkPrimarySoft
            Text(displayName.first.map { String($0).uppercased() } ?? "?")
                .font(.fkHeadlineSmall)
                .foregroundStyle(Color.fkPrimary)
        }
    }

    // MARK: Save

    private var saveButton: some View {
        Button {
            Task {
                await store.save(displayName: displayName, nickname: nickname, newAvatar: pickedAvatar)
                if store.errorMessage == nil, mode == .settings { dismiss() }
                // onboarding: needsProfileSetup flips false on success → the
                // root cover auto-dismisses; on failure the banner stays.
            }
        } label: {
            HStack(spacing: FkSpacing.sm) {
                if store.isSaving { ProgressView().tint(Color.fkOnPrimary) } else { Image(systemName: "checkmark") }
                Text(store.isSaving ? "保存中…" : "保存")
            }
            .font(.fkLabelLarge)
            .foregroundStyle(Color.fkOnPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(canSave ? Color.fkPrimary : Color.fkOutlineVariant))
        }
        .buttonStyle(.fkPressable)
        .disabled(!canSave)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: FkSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.fkDanger)
            Text(message).font(.fkBodySmall).foregroundStyle(Color.fkDanger)
            Spacer(minLength: 0)
        }
        .padding(FkSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: FkRadius.sm, style: .continuous).fill(Color.fkDangerSoft))
    }

    /// Downscale to ≤512px and JPEG-encode (~0.8) so avatars stay small in Storage.
    private func compressed(_ data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let maxSide: CGFloat = 512
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.8) ?? data
    }
}
```

> 设计系统组件（`FkCard` / `FkFormField` / `FkTextFieldPill` / `FkSpacing` / `Color.fk*` / `.buttonStyle(.fkPressable)`）均为项目既有，用法见 `HouseholdView.swift`。

- [ ] **Step 2: 编译验证**

Run: `xcodebuild build -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: Commit**

```bash
git add apps/ios/FreshPantry/Features/Settings/ProfileEditView.swift
git commit -m "feat(ios): ProfileEditView（头像 PhotosPicker + 名称/昵称,编辑/onboarding 共用）"
```

---

## Task 10: Settings 入口 + 成员行显示

**Files:**
- Modify: `apps/ios/FreshPantry/Features/Settings/SettingsView.swift`
- Modify: `apps/ios/FreshPantry/Features/Household/HouseholdView.swift`

> UI 接线；以编译 + 手动验证为准。

- [ ] **Step 1: Settings 加「个人资料」入口**

在 `SettingsView.swift` 的 `accountSection`（`apps/ios/FreshPantry/Features/Settings/SettingsView.swift:121-148`）里，`账号` 这个 `NavigationLink` 之前插入一个个人资料行。`accountSection` 用 `.sheet` 打开 `ProfileEditView`，需要一个 `@State` 标志 —— 在 `SettingsContent` 的 `@State` 区加：

```swift
    @State private var showProfileEditor = false
```

把 `accountSection` 改为（仅展示改动后的 `Section` 内容首部）：

```swift
    private var accountSection: some View {
        Section {
            Button {
                showProfileEditor = true
            } label: {
                SettingsLinkLabel(
                    systemImage: "person.text.rectangle",
                    title: "个人资料",
                    subtitle: profileSubtitle
                )
            }
            .buttonStyle(.plain)
            NavigationLink {
                LoginView(auth: auth)
            } label: {
                SettingsLinkLabel(
                    systemImage: accountIcon,
                    title: "账号",
                    subtitle: accountSubtitle
                )
            }
            NavigationLink {
                HouseholdView()
            } label: {
                SettingsLinkLabel(
                    systemImage: "house.and.flag",
                    title: "家庭共享",
                    subtitle: householdSubtitle,
                    showBadge: pendingInviteCount > 0
                )
            }
        } header: {
            Text("账号 · 家庭")
        } footer: {
            Text("登录后可创建或加入家庭,在成员间同步库存、采购与食谱。")
        }
        .listRowBackground(Color.fkSurfaceContainerLowest)
        .sheet(isPresented: $showProfileEditor) {
            ProfileEditView(store: dependencies.profileStore, mode: .settings)
        }
    }

    /// 个人资料 row subtitle: the live display name, or a prompt when unset.
    private var profileSubtitle: String {
        let name = dependencies.profileStore.displayName.trimmed
        return name.isEmpty ? "设置头像与名称" : name
    }
```

并在 `SettingsContent.body` 的 `.task { ... }` 里追加一次 profile 加载（让 subtitle 立即有值）：

```swift
        .task {
            permissionGranted = await notifications.refreshPermission()
            await loadStats()
            await loadHousehold()
            await dependencies.profileStore.load(signedIn: auth.signedInEmail != nil)
        }
```

- [ ] **Step 2: 成员行显示头像 + resolvedName**

在 `HouseholdView.swift` 的 `ActiveHouseholdSection` 加 `@Environment(AppDependencies.self)`（用于拿 `remotePantryRepository` 拼头像 URL）。在 `private var isOwner: Bool { ... }` 之上加：

```swift
    @Environment(AppDependencies.self) private var dependencies
```

把 `memberRow`（`apps/ios/FreshPantry/Features/Household/HouseholdView.swift:449-481`）的头像 `ZStack` + 名称 `Text` 替换为：

```swift
    private func memberRow(_ member: HouseholdMember) -> some View {
        HStack(spacing: FkSpacing.md) {
            memberAvatar(member)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.resolvedName)
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurface)
                Text(member.role == "owner" ? "所有者" : "成员")
                    .font(.fkLabelSmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
            Spacer(minLength: 0)
            if isOwner, member.role != "owner" {
                Button {
                    memberToRemove = member
                } label: {
                    Image(systemName: "person.badge.minus")
                        .foregroundStyle(Color.fkDanger)
                }
                .buttonStyle(.fkPressable)
                .disabled(store.isSubmitting)
            }
        }
    }

    /// Avatar from the member's stored path (public URL), falling back to the
    /// initial of resolvedName.
    @ViewBuilder
    private func memberAvatar(_ member: HouseholdMember) -> some View {
        let url = dependencies.remotePantryRepository?.avatarPublicURL(path: member.avatarPath)
        ZStack {
            Circle().fill(Color.fkPrimarySoft).frame(width: 36, height: 36)
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    memberInitial(member)
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            } else {
                memberInitial(member)
            }
        }
    }

    private func memberInitial(_ member: HouseholdMember) -> some View {
        Text(member.resolvedName.first.map { String($0).uppercased() } ?? "?")
            .font(.fkLabelLarge)
            .foregroundStyle(Color.fkPrimary)
    }
```

> `avatarPublicURL` 是 `RemotePantryRepository` 上的 `nonisolated` 方法（Task 6），可从 `@MainActor` 视图同步调用。

- [ ] **Step 3: 编译验证**

Run: `xcodebuild build -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED。

- [ ] **Step 4: Commit**

```bash
git add apps/ios/FreshPantry/Features/Settings/SettingsView.swift apps/ios/FreshPantry/Features/Household/HouseholdView.swift
git commit -m "feat(ios): Settings 个人资料入口 + 家庭成员行显示头像/名称"
```

---

## Task 11: 登录后 onboarding gate

**Files:**
- Modify: `apps/ios/FreshPantry/App/RootView.swift`

> 这是用户可见的「新用户填写」入口。以编译 + 模拟器手动验证为准。

- [ ] **Step 1: 加 profile gate 状态与加载**

在 `RootView` 的 `@State` 区（`@State private var showSearch = false` 之后）加：

```swift
    /// Drives the post-login onboarding profile cover (forces a display name).
    @State private var profileGateReady = false
```

> `ProfileStore` 本身在 `AppDependencies` 里共享，这里只需触发其 `load` 并读 `needsProfileSetup`。

在 `tabs` 的 `.task(id: dependencies.authService.signedInEmail)`（`RootView.swift:263-278` 的自动选家庭 task）末尾，`await store.refreshHouseholds()` 之后追加 profile 加载：

```swift
            await dependencies.profileStore.load(signedIn: true)
            profileGateReady = true
```

并在该 task 的开头 `guard ... else { return }` 失败分支前，处理登出时重置（在 `guard dependencies.authService.signedInEmail != nil else { ... }` 里）：

```swift
        .task(id: dependencies.authService.signedInEmail) {
            guard dependencies.authService.signedInEmail != nil else {
                profileGateReady = false
                return
            }
            await dependencies.clientProvider.ensureSessionReady()
            let store = HouseholdSessionStore(
                remote: dependencies.remotePantryRepository,
                session: dependencies.syncSession,
                auth: dependencies.authService,
                inventory: dependencies.inventoryRepository,
                shopping: dependencies.shoppingRepository,
                customRecipe: dependencies.customRecipeRepository,
                mealPlan: dependencies.mealPlanRepository
            )
            await store.refreshHouseholds()
            await dependencies.profileStore.load(signedIn: true)
            profileGateReady = true
        }
```

- [ ] **Step 2: 挂 `.fullScreenCover`**

在 `tabs` 的修饰符链上（例如紧接 `.environment(pendingSync)` 之后）加：

```swift
        // POST-LOGIN ONBOARDING: force a display name once signed in. The cover
        // shows only after profile load resolved (profileGateReady) AND the store
        // reports needsProfileSetup; saving a name flips it false → auto-dismiss.
        .fullScreenCover(isPresented: profileSetupBinding) {
            ProfileEditView(store: dependencies.profileStore, mode: .onboarding)
        }
```

并在 `RootView` 加这个 binding（放在 `invitePreviewBinding` 计算属性附近）：

```swift
    /// Presents the onboarding profile cover when load resolved + a display name
    /// is still missing. Read-only setter (the cover dismisses by the store's
    /// state flipping, never by user cancel).
    private var profileSetupBinding: Binding<Bool> {
        Binding(
            get: { profileGateReady && dependencies.profileStore.needsProfileSetup },
            set: { _ in }
        )
    }
```

- [ ] **Step 3: 编译验证**

Run: `xcodebuild build -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED。

- [ ] **Step 4: 手动验证（模拟器，需配置了 Supabase 后端的 build）**

1. 全新登录一个**没有 profile** 的邮箱 → 登录成功后**自动弹出**「完善个人信息」全屏页，不可下滑关闭。
2. 不填名称时「保存」按钮禁用；填入名称 → 保存 → 全屏页自动消失，进入主界面。
3. 进入 设置 → 个人资料 → 改昵称、换头像 → 保存 → 返回，Settings 行 subtitle 显示新名称。
4. 设置 → 家庭共享 → 成员列表中自己这行显示头像 + 名称（非 email）。
5. 断网下保存 → 出现「已在本地保留」提示，`hasPendingUpload` 为真；恢复网络后重新进入个人资料（触发 `load` → `retryPendingUpload`）应清除 pending。
6. 已有 display_name 的老用户登录 → **不**弹 onboarding。

- [ ] **Step 5: Commit**

```bash
git add apps/ios/FreshPantry/App/RootView.swift
git commit -m "feat(ios): 登录后 onboarding 强制填写个人信息(显示名)"
```

---

## Final Verification

- [ ] 全量测试通过

Run: `xcodebuild test -scheme FreshPantry -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: 所有测试 PASS（含新增 `ProfileModelsTests` / `ProfileRepositoryTests` / `HouseholdMemberTests` / `ProfileStoreTests`）。

- [ ] pgTAP 通过：`supabase test db` → 83/83。
- [ ] 扫一遍 `git diff main...feat/personal-profile`：无 `deleted_at`/version 列误加到 profiles；无静默吞错误；onboarding 不可绕过显示名；成员行回退链 nickname→displayName→email 正确。

---

## Notes / 已知取舍

- **头像缓存**：用「每次新 uuid 文件名」破缓存，旧对象不清理（自用 app 量小可接受）。若日后要清理，加一个删除旧 path 的步骤即可。
- **Storage RLS 自动化测试**：pgTAP 测 `storage.objects` 不便，本计划未覆盖；靠 migration 的 owner-only-prefix policy + Task 11 手动验证保证。
- **Flutter 对等**：本计划 iOS-only；`profiles` 列与 RPC 改动两端共享，Flutter 客户端补齐另开任务。
- **同步范式**：profile 刻意不接 `HouseholdContentSyncCoordinator`（household-scoped）；单写者轻量直写 + pending 重试，避免污染 content 同步的版本不变式。
