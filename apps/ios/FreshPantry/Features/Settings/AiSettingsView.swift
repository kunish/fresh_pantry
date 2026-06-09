import SwiftUI

/// AI 助手 sub-screen: an OpenAI-compatible endpoint config form (baseUrl / apiKey
/// / model / timeout) bound to the Keychain-backed `AiSettingsStore`.
///
/// Edits a local draft seeded from the store; 保存 persists the whole blob to the
/// Keychain via the store and pops. An `isConfigured` indicator reflects the
/// CURRENTLY SAVED settings. The live connection-test probe is OUT OF SCOPE for
/// this slice (AI feature phase); only storage + UI are built here.
struct AiSettingsView: View {
    let store: AiSettingsStore

    @Environment(\.dismiss) private var dismiss

    @State private var baseUrl: String
    @State private var apiKey: String
    @State private var model: String
    @State private var timeoutText: String

    init(store: AiSettingsStore) {
        self.store = store
        let s = store.settings
        _baseUrl = State(initialValue: s.baseUrl)
        _apiKey = State(initialValue: s.apiKey)
        _model = State(initialValue: s.model)
        _timeoutText = State(initialValue: String(Int(s.timeout)))
    }

    var body: some View {
        Form {
            Section {
                statusRow
            }
            .listRowBackground(Color.fkSurfaceContainerLowest)

            Section {
                LabeledField(label: "Base URL", text: $baseUrl, placeholder: "https://cpa.kunish.eu.org/v1", keyboard: .URL)
                SecureField("API Key", text: $apiKey)
                    .font(.fkBodyMedium)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                LabeledField(label: "Model", text: $model, placeholder: "gpt-4o")
                LabeledField(label: "Timeout (秒)", text: $timeoutText, placeholder: "60", keyboard: .numberPad)
            } header: {
                Text("连接配置")
            } footer: {
                Text("API Key 加密存储于设备钥匙串(Keychain),不上传同步。")
            }
            .listRowBackground(Color.fkSurfaceContainerLowest)
        }
        .scrollContentBackground(.hidden)
        .background(Color.fkSurface)
        .navigationTitle("AI 设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
            }
        }
        .tint(.fkPrimary)
    }

    private var statusRow: some View {
        HStack(spacing: FkSpacing.sm) {
            Image(systemName: store.isConfigured ? "checkmark.seal.fill" : "exclamationmark.circle")
                .foregroundStyle(store.isConfigured ? Color.fkSuccess : Color.fkOutline)
            Text(store.isConfigured ? "已配置" : "尚未配置")
                .font(.fkBodyMedium)
                .foregroundStyle(Color.fkOnSurface)
            Spacer()
        }
    }

    private func save() {
        let timeout = TimeInterval(Int(timeoutText.trimmed) ?? 60)
        let next = AiSettings(
            baseUrl: baseUrl.trimmed,
            apiKey: apiKey.trimmed,
            model: model.trimmed,
            timeout: timeout
        )
        store.save(next)
        dismiss()
    }
}

/// A two-line labeled text field row for the AI config form.
private struct LabeledField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.fkLabelMedium)
                .foregroundStyle(Color.fkOnSurfaceVariant)
            TextField(placeholder, text: $text)
                .font(.fkBodyMedium)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.vertical, 2)
    }
}
