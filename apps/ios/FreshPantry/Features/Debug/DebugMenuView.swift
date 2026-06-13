import SwiftUI

/// 隐藏的「调试菜单」,由 Settings「版本」行连点 7 次解锁(见 `DebugMenuGate`)。
/// 把每个 `FeatureFlag` 列为绑定到共享 `FeatureFlagStore` 的开关,另加重置全部 /
/// 重新锁定。同 Settings 其余部分,从注入的 `AppDependencies` 读取 store。
struct DebugMenuView: View {
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        let store = dependencies.featureFlagStore
        let gate = dependencies.debugMenuGate

        Form {
            Section {
                ForEach(FeatureFlag.allCases, id: \.self) { flag in
                    Toggle(isOn: Binding(
                        get: { store.isEnabled(flag) },
                        set: { store.set(flag, $0) }
                    )) {
                        VStack(alignment: .leading, spacing: FkSpacing.xs) {
                            Text(flag.title)
                                .font(.fkBodyMedium)
                                .foregroundStyle(Color.fkOnSurface)
                            Text(store.isOverridden(flag)
                                ? "\(flag.summary) · 已覆盖"
                                : "\(flag.summary) · 默认")
                                .font(.fkBodySmall)
                                .foregroundStyle(Color.fkOnSurfaceVariant)
                        }
                    }
                }
            } header: {
                Text("功能开关")
            }
            .listRowBackground(Color.fkSurfaceContainerLowest)

            Section {
                Button("重置全部为默认") { store.resetAll() }
                    .foregroundStyle(Color.fkPrimary)
                Button(role: .destructive) { gate.lock() } label: {
                    Text("锁定调试菜单")
                }
            } header: {
                Text("操作")
            }
            .listRowBackground(Color.fkSurfaceContainerLowest)
        }
        .scrollContentBackground(.hidden)
        .background(Color.fkSurface)
        .tint(.fkPrimary)
        .navigationTitle("调试菜单")
        .navigationBarTitleDisplayMode(.inline)
    }
}
