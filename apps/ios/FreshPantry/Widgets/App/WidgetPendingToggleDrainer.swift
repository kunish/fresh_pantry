import Foundation
import FreshPantryWidgetKit

/// **app 侧**:把 widget 攒下的「待落库勾选」真正落库。widget 进程只 append 了
/// itemID 到 App Group 队列(不碰 SwiftData);这里在主进程经 `ShoppingToggleService`
/// 逐条翻转 store + 记 outbox,再用权威数据重写展示快照(覆盖 widget 的乐观补丁)。
/// 在启动/家庭就绪/回前台时调用,与 `IntentAddDrainer` 同位。
enum WidgetPendingToggleDrainer {
    static func drain(dependencies: AppDependencies) async {
        let ids = WidgetPendingToggleStore.drain()
        guard !ids.isEmpty else { return }
        for id in ids {
            _ = await ShoppingToggleService.toggle(
                container: dependencies.modelContainer,
                householdID: dependencies.householdID,
                itemID: id,
                clientID: dependencies.syncSession.clientId,
                now: .now
            )
        }
        await WidgetSnapshotPublisher.publish(
            container: dependencies.modelContainer,
            householdID: dependencies.householdID
        )
    }
}
