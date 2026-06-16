import Foundation
import SwiftData

/// 小组件交互勾选的可测核心。翻转共享 store 里某购物项的 `isChecked`,并在有
/// 家庭作用域时直接记一条 `.toggleChecked` outbox 操作(刻意不经 `SyncWriter`,
/// 那会把 `SyncCoordinator`→Supabase 网络层拖进 widget)。app 下次前台用既有
/// `SyncCoordinator` 推送这条 op。完整对齐 `ShoppingStore.toggleChecked` 的写口径。
enum ShoppingToggleService {
    /// 返回是否翻转成功(目标行不存在 / 写失败 → false)。
    @discardableResult
    static func toggle(container: ModelContainer, householdID: String, itemID: String, clientID: String, now: Date) async -> Bool {
        let shopping = ShoppingRepository(modelContainer: container)
        guard let all = try? await shopping.loadAllFor(householdID),
              let prior = all.first(where: { $0.id == itemID }) else { return false }

        let toggled = prior.copyWith(isChecked: !prior.isChecked)
        guard (try? await shopping.updateRow(householdID, toggled)) == true else { return false }

        // 仅本地(无家庭)→ 已持久化,无需 outbox(无远程可推)。
        guard !householdID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }

        let outbox = SyncOutboxRepository(modelContainer: container)
        let op = SyncOperation(
            id: UUID().uuidString.lowercased(),
            householdId: householdID,
            entityType: .shoppingItem,
            entityId: toggled.id,
            operation: .toggleChecked,
            patch: ["isChecked": .bool(toggled.isChecked)],
            baseVersion: prior.remoteVersion,
            clientId: clientID,
            createdAt: now
        )
        try? await outbox.enqueue(op)
        return true
    }
}
