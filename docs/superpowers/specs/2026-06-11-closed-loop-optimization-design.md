# 全仓交互/逻辑闭环优化 — 设计稿（2026-06-11）

> 多智能体审计（10 区域侦察 + 逐发现对抗式核实，66 agent）确认 56 项闭环缺口、0 项驳回。
> 本稿把它们去重为 **12 个工作流（约 40 个独立项）**，按文件归属分三波实现，
> 每波之间构建门禁，最后全量测试 + 对抗式 review。明细（证据 file:line、核实
> notes）见审计输出归档；实现时以各工作流 JSON 为准。

## 审计方法

- 八类缺口口径：dead-control / dead-setting / broken-flow / no-feedback /
  stale-state / inconsistent / swallowed-error / data-loop。
- 每个发现都经独立对抗式核实代理驳验（证据逐行 Read、全仓 grep 反证、
  对照 parity-gaps 文档的有意 defer 记录、按自用模式评估价值）。

## 阻塞项（已先行修复）

**主干编译断裂**：提交 2cf061d 只交付了 `profileCardSection` 的调用点与
`ProfileDetailView`，定义（`ProfileCardRow`/`ProfileCardModel`/`profileFamilyLine`/
`profileSyncLine`）以及 `MemberAvatar` 组件从未入库。已按该提交说明与
`2026-06-11-settings-profile-card` 计划重建：新建共享组件
`DesignSystem/Components/MemberAvatar.swift`，SettingsView 补齐卡片 section
（NavigationLink → ProfileDetailView），补 `ProfileCardModelTests`（4 例）。

## 十二个工作流

### 第 1 波（文件互斥，6 个并行代理）

**WS1 通知提醒闭环**（8 项收敛）— 根因：`NotificationCoordinator.permissionGranted`
内存态冷启动恒 false，reschedule 整条静默短路；且重排只挂在前台 `.active` 一个
时机。修复：reschedule 前先刷新真实权限；增加触发时机（进后台 `.background`
一次性重排，覆盖会话内全部库存变更；远端合并 dataRevision、household 切换）；
实现 `willPresent`（前台横幅）；「每日汇总」副标题与实际内容对齐。
文件：NotificationCoordinator、ExpiryScheduler、RootView、FreshPantryApp、
SettingsView（仅文案行）。

**WS4 购物闭环**（5 项）— 高危：跨页面「加购」使用会话级陈旧 ShoppingStore
快照整表覆写，可静默删行（写放大）。修复：写前重读或改 scoped 写入；Siri
drain 后通知前台刷新；入库审核 persist 失败显式报错；openIntake 不再吞库存
加载错误；「清空已完成」补撤销。
文件：ShoppingStore、ShoppingView、IntakeReviewView/IntakeController。

**WS7 菜谱闭环**（6 项）— 编辑保存后详情/列表刷新；扣减失败 toast；扣减后
重算匹配；烹饪模式「完成」回写勾选并衔接做菜扣减；AI 解析覆盖前确认；
封面孤儿文件清理。
文件：RecipesStore、RecipeDetailView、CustomRecipeFormView、烹饪模式视图、
RecipeCoverStore。

**WS9 膳食计划闭环**（5 项）— 完成计划餐衔接「做菜扣减」流（断链补环）；
计划行可点进菜谱详情；缺料统计口径与「本周」文案对齐（按周视图过滤）；
懒建 store 随 household/dataRevision 刷新；写失败反馈；goToToday 入口。
文件：MealPlanView、MealPlanStore。

**WS3 备份闭环**（4 项）— 备份补 FoodLog/收藏/忌口/饮食偏好/提醒设置（或
文案不再自称「全部数据」，二选一取前者）；导入走 SyncWriter/outbox 防远端
merge 回滚。文件：BackupService、BackupView。

**WS12 设置杂项**（2 项）— Profile 待同步在前台恢复时真正重试；AI 设置
Keychain 写失败不再假装成功。文件：ProfileStore、AiSettingsView。

### 第 2 波（4 个并行代理）

**WS5 首页刷新闭环**（6 项）— 主数据随子页变更/pop 刷新；household 切换重建
二级 store；临期预览加购 store 未就绪时禁用而非 no-op；LowStockView 死反馈
状态接 toast；减废屏/首页减废卡消费 dataRevision。
文件：DashboardView、DashboardStore、LowStockView、WasteInsights 屏。

**WS2 FoodLog 记账闭环**（4 项）— 批量删除补「吃完/扔了」去向追问（对齐
单条删除）；createHousehold 收养迁移补 FoodLog；append 失败不再 try? 吞。
文件：InventoryStore、InventoryView、HouseholdSessionStore（仅 adoption 函数）、
FoodLog 仓库。

**WS6 临期屏闭环**（3 项）— 「用了」消费撤销句柄（对齐详情页撤销横幅）；
从详情返回后刷新列表。文件：ExpiringView、ExpiringStore。

**WS11 外部入口反馈**（2 项）— Spotlight 命中已删条目给 toast；ShareExtension
不支持的分享给提示而非静默关闭。文件：SpotlightRouter/RootView、ShareExtension。

### 第 3 波（2 个并行代理）

**WS10 会话/同步状态机**（8 项）— 登出调用 stop() 并清 selectedHouseholdId
（消灭死代码）；HouseholdView 随登录态刷新；未登录/local-only 深链给「请先
登录」反馈；发邀请后刷新 owner 列表；outbox 永久失败死信化（横幅不再永远
「同步中」）；离线启动后网络恢复重试入站同步。
文件：HouseholdSessionStore、HouseholdView、SyncSession/SyncCoordinator、RootView。

**WS8 库存录入杂项**（2 项）— 入库/编辑/删除持久化失败上浮；PhotosPicker
解析失败后重置选择（重试可用）。文件：AddIngredient 表单、IntakeController。

## 实现纪律

- 每代理只触碰其文件清单 + 自己的新测试文件；波间构建门禁，波内文件互斥。
- 新逻辑优先抽纯函数/Store 方法配单测（沿用仓库 TDD 惯例）；视图接线靠
  编译 + 既有测试回归。
- 全部完成后：全量测试 → 多代理对抗式 review → 修复 → 再全量测试 → 提交
  （conventional commits，按工作流分组）。

## 非目标

- 不引入新功能面（纯闭环收口）；不动 supabase schema；不动 CI；
  审计确认为「有意 defer 且理由仍成立」的项不做。
