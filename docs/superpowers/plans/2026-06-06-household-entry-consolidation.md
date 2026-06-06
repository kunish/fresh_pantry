# 家庭管理入口收敛 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把家庭管理的两个并列一级入口(Dashboard 家庭 Chip + Settings「家庭共享」行)收敛为 Settings 唯一入口,并把邀请提醒红点从被删的 Chip 搬到顶栏设置齿轮与 Settings「家庭共享」行。

**Architecture:** 纯 UI 入口层改动。所有家庭操作早已统一走 `householdSessionControllerProvider`(单一 source of truth),本计划不碰状态/同步/数据层。先在新位置(齿轮)立起邀请提醒,再删旧 Chip,最后补 Settings 行红点,保证通知能力全程不丢失。

**Tech Stack:** Flutter / Riverpod (StateNotifier) / flutter_test widget tests。所有命令在 `apps/mobile` 目录下执行。测试沿用既有 `test/helpers/household_gateway_stub.dart` 与 `test/support/test_database.dart` 脚手架。

---

## File Structure

| 文件 | 职责 | 动作 |
|------|------|------|
| `apps/mobile/lib/widgets/common/top_app_bar.dart` | 首页顶栏(logo/设置齿轮/搜索) | 改:齿轮加邀请红点 |
| `apps/mobile/lib/screens/dashboard_screen.dart` | 首页 | 改:移除 Chip 引用 |
| `apps/mobile/lib/widgets/dashboard/household_chip.dart` | 旧家庭 Chip | 删 |
| `apps/mobile/lib/screens/settings_screen.dart` | 设置页(含家庭共享行 + `_LinkRow`) | 改:`_LinkRow` 加红点,家庭行启用 |
| `apps/mobile/test/top_app_bar_test.dart` | 顶栏测试 | 改:补 household override + 加齿轮红点测试 |
| `apps/mobile/test/household_chip_test.dart` | 旧 Chip 测试 | 删 |
| `apps/mobile/test/settings_household_badge_test.dart` | 家庭行红点测试 | 建 |

**关键约束(已核实):**
- 给 `TopAppBar` 加 `watch(householdSessionControllerProvider)` 后,任何 pump `TopAppBar` 但未提供 household 依赖的测试会因实例化真实 gateway(依赖 Supabase)而崩。经核查只有 `top_app_bar_test.dart` 的搜索测试缺该 override(其余 Dashboard 系测试因现有 Chip 已 watch 该 provider,早已具备 override)。Task 1 必须修这个搜索测试。
- `_LinkRow` 在 settings 中被复用 6 处,只有家庭行(L240)会设 `showBadge: true`,故红点 key `household_row_invite_badge` 唯一。
- Settings body 是 `ListView.builder(itemBuilder: sections[index])`,家庭行是靠顶部的 section(约第 6 项),初始视口内会被构建,`find.byKey` 无需滚动即可命中。

---

### Task 1: 顶栏设置齿轮加邀请红点

**Files:**
- Modify: `apps/mobile/lib/widgets/common/top_app_bar.dart`
- Test: `apps/mobile/test/top_app_bar_test.dart`

- [ ] **Step 1: 改写顶栏测试 — 补 household override + 新增两个齿轮红点测试**

把 `apps/mobile/test/top_app_bar_test.dart` 整个替换为:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/providers/navigation_provider.dart';
import 'package:fresh_pantry/widgets/common/top_app_bar.dart';

import 'helpers/household_gateway_stub.dart';

Future<HouseholdSessionController> _seeded({
  List<HouseholdInvitePreview> invites = const [],
}) async {
  final stub = HouseholdGatewayStub(
    isAuthenticated: true,
    households: const [
      Household(
        id: 'h1',
        name: '我家',
        ownerId: 'owner_1',
        defaultStorageArea: 'fridge',
      ),
    ],
    pendingInvites: invites,
  );
  final controller = HouseholdSessionController(stub);
  await controller.refreshHouseholds();
  await controller.switchHousehold('h1');
  await controller.refreshPendingInvites();
  return controller;
}

const _sampleInvite = HouseholdInvitePreview(
  inviteId: 'inv1',
  householdId: 'h9',
  householdName: '李家',
  ownerEmail: 'o@ex.com',
  invitedEmail: 'me@ex.com',
  memberCount: 1,
  inventoryCount: 0,
  shoppingCount: 0,
  customRecipeCount: 0,
);

void main() {
  testWidgets('search button activates the search overlay provider', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        householdGatewayProvider.overrideWithValue(HouseholdGatewayStub()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(body: TopAppBar()),
        ),
      ),
    );

    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();

    expect(container.read(searchActiveProvider), isTrue);
  });

  testWidgets('settings gear shows invite badge when there is a pending invite',
      (tester) async {
    final controller = await _seeded(invites: const [_sampleInvite]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          householdSessionControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: Scaffold(body: TopAppBar())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings_invite_badge')),
      findsOneWidget,
    );
  });

  testWidgets('settings gear has no badge without pending invites',
      (tester) async {
    final controller = await _seeded();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          householdSessionControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: Scaffold(body: TopAppBar())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings_invite_badge')),
      findsNothing,
    );
  });
}
```

- [ ] **Step 2: 跑测试确认红点测试失败、搜索测试通过**

Run: `cd apps/mobile && flutter test test/top_app_bar_test.dart`
Expected: `search button...` PASS;两个 `settings gear...` 测试 FAIL(齿轮尚无 `settings_invite_badge`,有邀请那条断言 findsOneWidget 失败;无邀请那条会 PASS)。即至少「有邀请显示红点」一条为红。

- [ ] **Step 3: 实现 — 顶栏 watch 会话并给齿轮加红点**

在 `apps/mobile/lib/widgets/common/top_app_bar.dart` 顶部 import 区(现有 import 之后)加:

```dart
import '../../household/household_session_controller.dart';
```

在 `build` 方法体最前面(`return SizedBox(` 之前)加一行:

```dart
    final hasInvite = ref.watch(
      householdSessionControllerProvider.select(
        (s) => s.pendingInvitePreviews.isNotEmpty,
      ),
    );
```

把设置齿轮那个 `IconButton`(`Icons.settings_outlined`)整体替换为 `Stack` 包裹:

```dart
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.settings_outlined,
                        color: Colors.white,
                      ),
                      tooltip: '设置',
                      onPressed: () {
                        Navigator.of(context).push(
                          fkRoute<void>(builder: (_) => const SettingsScreen()),
                        );
                      },
                    ),
                    if (hasInvite)
                      Positioned(
                        right: 8,
                        top: 10,
                        child: IgnorePointer(
                          child: Container(
                            key: const ValueKey('settings_invite_badge'),
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.fkAlert,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
```

- [ ] **Step 4: 跑测试确认全绿**

Run: `cd apps/mobile && flutter test test/top_app_bar_test.dart`
Expected: 3 个测试全部 PASS。

- [ ] **Step 5: 提交**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry
git add apps/mobile/lib/widgets/common/top_app_bar.dart apps/mobile/test/top_app_bar_test.dart
git commit -m "feat(household): 顶栏设置齿轮显示邀请红点"
```

---

### Task 2: 删除 Dashboard 家庭 Chip

**Files:**
- Modify: `apps/mobile/lib/screens/dashboard_screen.dart`(移除 import 与用法)
- Delete: `apps/mobile/lib/widgets/dashboard/household_chip.dart`
- Delete: `apps/mobile/test/household_chip_test.dart`

- [ ] **Step 1: 从 Dashboard 移除 Chip import**

在 `apps/mobile/lib/screens/dashboard_screen.dart` 删除这一行:

```dart
import '../widgets/dashboard/household_chip.dart';
```

- [ ] **Step 2: 从 Dashboard hero 移除 Chip,并把外层 Row 还原为问候 Column**

把这段(hero 标题处的 `Row`):

```dart
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            greeting,
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '你的冰箱状态',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: AppFontSize.xxl,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    const HouseholdChip(),
                  ],
                ),
```

替换为:

```dart
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '你的冰箱状态',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: AppFontSize.xxl,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
```

- [ ] **Step 3: 删除旧 Chip 测试(它 import 了即将删除的 widget)**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry
git rm apps/mobile/test/household_chip_test.dart
```

- [ ] **Step 4: 删除 Chip widget 文件**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry
git rm apps/mobile/lib/widgets/dashboard/household_chip.dart
```

- [ ] **Step 5: 静态分析确认无悬挂引用 / 死 import**

Run: `cd apps/mobile && flutter analyze lib/screens/dashboard_screen.dart`
Expected: No issues(无 `HouseholdChip` 未定义、无 unused import)。

- [ ] **Step 6: 跑 Dashboard 相关测试确认未回归**

Run: `cd apps/mobile && flutter test test/dashboard_screen_test.dart test/dashboard_widget_test.dart`
Expected: 全部 PASS(这些测试不引用 Chip;它们已具备 household gateway override,因此顶栏新 watch 不受影响)。

- [ ] **Step 7: 提交**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry
git add apps/mobile/lib/screens/dashboard_screen.dart
git commit -m "refactor(household): 删除 Dashboard 家庭 Chip,入口收敛到 Settings"
```

---

### Task 3: Settings「家庭共享」行加邀请红点

**Files:**
- Modify: `apps/mobile/lib/screens/settings_screen.dart`(`_LinkRow` 加 `showBadge`;家庭行启用)
- Test: `apps/mobile/test/settings_household_badge_test.dart`(新建)

- [ ] **Step 1: 写失败测试**

新建 `apps/mobile/test/settings_household_badge_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/providers/notification_service_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/settings_screen.dart';
import 'package:fresh_pantry/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/household_gateway_stub.dart';
import 'support/test_database.dart';

Future<HouseholdSessionController> _seeded({
  List<HouseholdInvitePreview> invites = const [],
}) async {
  final stub = HouseholdGatewayStub(
    isAuthenticated: true,
    households: const [
      Household(
        id: 'h1',
        name: '我家',
        ownerId: 'owner_1',
        defaultStorageArea: 'fridge',
      ),
    ],
    pendingInvites: invites,
  );
  final controller = HouseholdSessionController(stub);
  await controller.refreshHouseholds();
  await controller.switchHousehold('h1');
  await controller.refreshPendingInvites();
  return controller;
}

Future<void> _pumpSettings(
  WidgetTester tester,
  HouseholdSessionController controller,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = newTestDatabase();
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...testStorageOverrides(database: db),
        notificationServiceProvider.overrideWithValue(NotificationService()),
        householdGatewayProvider.overrideWithValue(HouseholdGatewayStub()),
        householdSessionControllerProvider.overrideWith((ref) => controller),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

const _sampleInvite = HouseholdInvitePreview(
  inviteId: 'inv1',
  householdId: 'h9',
  householdName: '李家',
  ownerEmail: 'o@ex.com',
  invitedEmail: 'me@ex.com',
  memberCount: 1,
  inventoryCount: 0,
  shoppingCount: 0,
  customRecipeCount: 0,
);

void main() {
  testWidgets('household row shows invite badge with pending invites',
      (tester) async {
    final controller = await _seeded(invites: const [_sampleInvite]);
    await _pumpSettings(tester, controller);

    expect(
      find.byKey(const ValueKey('household_row_invite_badge')),
      findsOneWidget,
    );
  });

  testWidgets('household row has no badge without pending invites',
      (tester) async {
    final controller = await _seeded();
    await _pumpSettings(tester, controller);

    expect(
      find.byKey(const ValueKey('household_row_invite_badge')),
      findsNothing,
    );
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd apps/mobile && flutter test test/settings_household_badge_test.dart`
Expected: 「shows invite badge」FAIL(`_LinkRow` 还没有红点,findsOneWidget 失败);「no badge」PASS。即第一条为红。

- [ ] **Step 3: 给 `_LinkRow` 加 `showBadge` 参数**

在 `apps/mobile/lib/screens/settings_screen.dart` 的 `_LinkRow` 字段区加:

```dart
  final bool showBadge;
```

构造函数加形参(放在 `this.isLast = false,` 之后):

```dart
    this.showBadge = false,
```

在 `_LinkRow.build` 的 `Row` 里,把末尾的 chevron `Icon` 前面插入红点(即在 `const Icon(Icons.chevron_right_rounded, ...)` 之前):

```dart
              if (showBadge) ...[
                Container(
                  key: const ValueKey('household_row_invite_badge'),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.fkAlert,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
```

- [ ] **Step 4: 家庭行启用红点**

在 `apps/mobile/lib/screens/settings_screen.dart` 的家庭行 `_LinkRow`(`Key('household_entry_row')`)里,加一行参数(放在 `icon: Icons.home_rounded,` 之后):

```dart
                  showBadge: householdSession.pendingInvitePreviews.isNotEmpty,
```

- [ ] **Step 5: 跑测试确认全绿**

Run: `cd apps/mobile && flutter test test/settings_household_badge_test.dart`
Expected: 2 个测试全部 PASS。

- [ ] **Step 6: 提交**

```bash
cd /Users/shikun/Developer/opensource/fresh_pantry
git add apps/mobile/lib/screens/settings_screen.dart apps/mobile/test/settings_household_badge_test.dart
git commit -m "feat(household): Settings 家庭共享行显示邀请红点"
```

---

### Task 4: 全量验证

**Files:** 无改动(仅验证)。

- [ ] **Step 1: 全项目静态分析**

Run: `cd apps/mobile && flutter analyze`
Expected: 无新增告警/错误(尤其无残留对 `household_chip.dart` 的引用)。

- [ ] **Step 2: 全量测试(项目要求串行运行,避免 Drift/DB 并发问题)**

Run: `cd apps/mobile && flutter test --concurrency=1`
Expected: 全绿。重点确认:`household_chip_test.dart` 已删除无悬挂引用;`top_app_bar_test.dart`、`settings_household_badge_test.dart`、Dashboard 系测试全部 PASS。

- [ ] **Step 3: 冒烟核对(人工/描述)**

确认以下行为:
1. Dashboard 首页右上角不再有家庭 Chip,hero「问候 + 你的冰箱状态」布局正常。
2. 构造一个含 `pendingInvitePreviews` 的会话时:顶栏设置齿轮右上角显示红点;进入 Settings,「家庭共享」行右侧显示红点;点击该行可达 `HouseholdScreen`。
3. 无待处理邀请时:齿轮与家庭行均无红点。

- [ ] **Step 4: 若 Step 3 全部满足,本计划完成。** 无需额外提交(各 Task 已分别提交)。

---

## Self-Review

**Spec 覆盖:**
- 删除 Dashboard Chip → Task 2 ✓
- 邀请红点搬到顶栏齿轮 → Task 1 ✓
- Settings 行加同款红点 → Task 3 ✓
- 删除 `household_chip_test.dart` + 新增齿轮红点测试 → Task 1/2 ✓
- 范围边界(`HouseholdScreen` 内部、`AuthGateScreen`、同步/数据层不动)→ 全计划未触及 ✓
- 验证(analyze / 串行 test / 冒烟)→ Task 4 ✓

**占位符扫描:** 无 TBD/TODO;每个代码步骤均给出完整代码。

**类型/命名一致性:**
- 红点 key:齿轮用 `settings_invite_badge`,Settings 行用 `household_row_invite_badge`,各任务内部前后一致。
- 颜色统一 `AppColors.fkAlert`(沿用原 Chip 红点色)。
- `_seeded` helper 在 Task 1、Task 3 两个测试文件内各自定义(独立文件,非跨文件引用),签名一致。
- `showBadge` 参数名在 `_LinkRow` 定义与家庭行调用处一致。
