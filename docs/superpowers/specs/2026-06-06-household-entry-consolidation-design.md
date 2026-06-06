# 家庭管理入口收敛设计

日期:2026-06-06
状态:已批准,待实现

## 目标

消除家庭管理功能的「多入口」:当前 Dashboard 首页右上角的家庭 Chip 与 Settings 设置页的「家庭共享」行是两个并列的一级入口,都跳转到同一个 `HouseholdScreen`,功能完全重复。本次将入口收敛为 **Settings 唯一入口**,并把家庭邀请的提醒红点从被删除的 Chip 搬到顶栏设置齿轮上,保证待处理邀请(时效性强,3 天过期)仍能被用户及时看到。

业务逻辑层不变:所有家庭操作早已统一走 `HouseholdSessionController`(单一 source of truth),本次仅改 UI 入口层。不碰同步链、数据层、`HouseholdScreen` 聚合页内部、`AuthGateScreen` 登录引导流。

## 现状(已核实)

- `HouseholdScreen` 的 push 站点只有两个:
  - `lib/widgets/dashboard/household_chip.dart:22` —— Dashboard hero 区的 Chip
  - `lib/screens/settings_screen.dart:248` —— Settings「家庭共享」行(`Key('household_entry_row')`)
- `HouseholdChip`(`lib/widgets/dashboard/household_chip.dart`):显示当前家庭名 + 下拉箭头,有待处理邀请时显示红点(`ValueKey('household_chip_badge')`),点击进 `HouseholdScreen`。在 `dashboard_screen.dart:18` import、`dashboard_screen.dart:430` 使用。
- `TopAppBar`(`lib/widgets/common/top_app_bar.dart`):已是 `ConsumerWidget`;设置齿轮 `IconButton` 在 L54-65。
- 待处理邀请来源:`householdSessionControllerProvider` 的 `pendingInvitePreviews`(收到的、别人邀我加入的邀请)。
- 测试:`test/household_chip_test.dart` 覆盖 Chip 的红点显隐与点击跳转。

## 改动方案

### 1. 删除 Dashboard 家庭 Chip
- 删除文件 `lib/widgets/dashboard/household_chip.dart`。
- `dashboard_screen.dart`:移除 `import '../widgets/dashboard/household_chip.dart';`(L18);移除 hero 标题行中的 `const HouseholdChip()` 及其前置间距 `SizedBox`(L429-430)。原 `Row` 此时只剩 `Expanded` 问候列,简化为直接使用该列(去掉多余的单子 Row 包装),保持 hero 布局视觉不变。

### 2. 邀请红点搬到顶栏设置齿轮
- `top_app_bar.dart`:watch `householdSessionControllerProvider.select((s) => s.pendingInvitePreviews.isNotEmpty)`。
- 用 Material `Badge`(`Badge(isLabelVisible: hasInvite, ...)` 小圆点形态)包住设置齿轮 `IconButton`,颜色用 `AppColors.fkAlert`(与原 Chip 红点一致)。
- 给红点一个测试 key:`ValueKey('settings_invite_badge')`。
- tooltip 在有邀请时可保持「设置」即可(不强制改文案)。

### 3. Settings「家庭共享」行加同款红点
- `settings_screen.dart`:`household_entry_row`(L240)保持跳转 `HouseholdScreen` 不变。
- 当 `householdSession.pendingInvitePreviews.isNotEmpty` 时,在该行右侧(或标题旁)显示同款红点,key `ValueKey('household_row_invite_badge')`。
- 形成完整通知路径:**顶栏齿轮红点 → Settings → 「家庭共享」行红点 → `HouseholdScreen` 处理邀请**。

### 4. 测试
- 删除 `test/household_chip_test.dart`。
- 新增顶栏齿轮红点测试(`test/top_app_bar_invite_badge_test.dart` 或就近):
  - 无 `pendingInvitePreviews` 时 `settings_invite_badge` 不显示。
  - 有 `pendingInvitePreviews` 时 `settings_invite_badge` 显示。
- 可选:对 Settings 行红点 `household_row_invite_badge` 做同样显隐断言(若 Settings 测试已有脚手架则就近加,否则视成本决定)。

## 范围边界(明确不做)

- `HouseholdScreen` 内部聚合页(切换家庭、成员管理、邀请创建、解散/退出)—— 本就是单页,不动。
- `AuthGateScreen` 的创建家庭 / 邀请预览 / 邀请提醒流 —— 一次性 onboarding,非日常管理入口,不动。
- 同步链(`selectedHouseholdIdStateProvider` 投影)、数据层、`HouseholdSessionController` —— 不动。
- 多家庭切换仍在 `HouseholdScreen` 内部(原 Chip 也只是跳转,从不直接切换),功能无损失。

## 验证

- 目标测试:新增的齿轮红点测试 + 受影响的 dashboard/settings widget 测试。
- `flutter analyze` 无新增告警(注意移除死 import)。
- `flutter test`(项目要求串行运行)全绿,尤其确认删除 `household_chip_test.dart` 后无悬挂引用。
- 冒烟:Dashboard 不再有 Chip 且布局正常;构造一个有 `pendingInvitePreviews` 的 session,确认齿轮与「家庭共享」行均显示红点,点击链路可达 `HouseholdScreen`。

## 风险

- 低。改动集中在 UI 入口层,不触及状态/同步/数据。
- 唯一行为变化:删除 Chip 后 Dashboard 不再直接展示「当前家庭名 / 本地数据」上下文——已与用户确认接受,该信息在 Settings「家庭共享」行可见。
