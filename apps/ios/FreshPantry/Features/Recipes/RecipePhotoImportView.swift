import PhotosUI
import SwiftUI

/// 拍照导入食谱 sheet: pick a photo / screenshot of a paper or chat recipe, run
/// on-device OCR (`TextRecognizer`), hand the recognized text to the AI text
/// parser (`AiRecipeParser.fromText`), and present the result in the editable
/// `CustomRecipeFormView` for the user to review before saving.
///
/// Reuses the EXISTING image-pick + downscale machinery (`PhotosPicker` +
/// `ImageDownscaler`, same as `ImageImportView`) and the EXISTING AI text →
/// `RecipeDraft` → form chain (the `initialGeneratedDraft` seam the 清冰箱
/// generator already feeds), so neither the photo pipeline nor the parse path is
/// duplicated. Gated on a configured AI provider — when unconfigured it shows the
/// same friendly "去设置配置 AI" note as the other AI flows.
///
/// Uses `PhotosUI.PhotosPicker` (out-of-process `PHPickerViewController`), so it
/// works in the simulator and needs NO `NSPhotoLibraryUsageDescription` key.
struct RecipePhotoImportView: View {
    /// CRUD owner passed in so the form's save wiring (sync/outbox) stays in one
    /// place — the form routes the reviewed recipe through `store.add`.
    let store: CustomRecipeStore
    /// AI provider config — gates the picker; unconfigured shows the设置 hint.
    let aiSettingsStore: AiSettingsStore
    /// Called after a successful save so the presenter can reload its list.
    var onSaved: () -> Void = {}

    /// Test seam: override the OCR text → `RecipeDraft` parse so the whole
    /// pick→OCR→parse→form flow is exercisable without Vision or the network. In
    /// prod it is nil and the live `TextRecognizer` + `AiRecipeParser` run.
    var parserOverride: (@Sendable (Data) async throws -> RecipeDraft)?

    /// Longest edge (in pixels) the picked image is downscaled to before OCR —
    /// bounds the work the Vision request does on a huge original.
    private static let maxImageDimension = 2048

    @Environment(\.dismiss) private var dismiss

    @State private var pickedItem: PhotosPickerItem?
    @State private var isProcessing = false
    /// Inline error (read photo / OCR / AI parse / not configured) — never silent.
    @State private var errorMessage: String?
    /// The parsed draft awaiting user review in the form sheet; presenting it pushes
    /// the editable `CustomRecipeFormView`.
    @State private var draftRoute: ParsedDraftRoute?

    var body: some View {
        NavigationStack {
            Group {
                if aiSettingsStore.isConfigured {
                    picker
                } else {
                    notConfigured
                }
            }
            .background(Color.fkSurface)
            .navigationTitle("拍照导入食谱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .disabled(isProcessing)
                }
            }
            .overlay {
                if isProcessing {
                    RecipePhotoImportBusyOverlay()
                }
            }
            .sheet(item: $draftRoute, onDismiss: { dismiss() }) { route in
                CustomRecipeFormView(
                    store: store,
                    aiSettingsStore: aiSettingsStore,
                    onSaved: onSaved,
                    initialGeneratedDraft: route.draft
                )
            }
        }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { await handlePicked(item) }
        }
    }

    // MARK: Picker

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FkSpacing.lg) {
                Text("选择一张纸质菜谱、手写菜谱或聊天截图，先离线识别文字，再由 AI 整理成食谱草稿供你核对。")
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurfaceVariant)

                PhotosPicker(
                    selection: $pickedItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    pickerLabel
                }
                .buttonStyle(.fkPressable)
                .disabled(isProcessing)

                if let errorMessage {
                    FkRecipePhotoNotice(systemImage: "exclamationmark.triangle", message: errorMessage)
                }
            }
            .padding(FkSpacing.lg)
        }
    }

    private var pickerLabel: some View {
        HStack(spacing: FkSpacing.sm) {
            Image(systemName: "text.viewfinder")
            Text("选择照片或截图")
                .font(.fkLabelLarge)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.fkOutline)
        }
        .foregroundStyle(Color.fkPrimary)
        .padding(FkSpacing.md)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous)
                .fill(Color.fkPrimarySoft)
        )
    }

    private var notConfigured: some View {
        FkEmptyState(
            systemImage: "wand.and.stars",
            title: "请先在设置中配置 AI",
            message: "在 设置 › AI 助手 填写 Base URL / API Key / 模型 后，即可拍照导入纸质或截图菜谱。"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    /// Loads the picked photo, downscales it off the main actor, OCRs it, asks the
    /// AI to structure the text, and presents the editable form on success. Every
    /// failure (read / decode / no-text / AI parse / not-configured) lands in
    /// `errorMessage` so it renders inline — nothing is swallowed.
    private func handlePicked(_ item: PhotosPickerItem) async {
        errorMessage = nil

        let data: Data?
        do {
            data = try await item.loadTransferable(type: Data.self)
        } catch {
            errorMessage = "读取照片失败：\(error.localizedDescription)"
            return
        }
        guard let data, !data.isEmpty else {
            errorMessage = "读取照片失败，请重试。"
            return
        }

        // Downscale off the main actor so a large image never blocks UI before OCR.
        let maxDimension = Self.maxImageDimension
        let resized = await Task.detached {
            ImageDownscaler.jpegData(from: data, maxDimension: maxDimension)
        }.value
        guard let resized else {
            errorMessage = "无法处理该照片，请换一张重试。"
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            let draft = try await parse(resized)
            draftRoute = ParsedDraftRoute(draft: draft)
        } catch let error as TextRecognizer.RecognizeError {
            errorMessage = error.message
        } catch let error as AiError {
            errorMessage = error.message
        } catch {
            errorMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    /// OCR the image (raw lines, joined — NOT the receipt cleaner, whose price/total
    /// filtering would strip real recipe lines) and structure it via the SHARED
    /// `AiRecipeParser.fromText`. Overridable so tests skip Vision + the network.
    private func parse(_ imageData: Data) async throws -> RecipeDraft {
        if let parserOverride { return try await parserOverride(imageData) }
        let lines = try await TextRecognizer.recognizeLines(from: imageData)
        let text = lines.joined(separator: "\n")
        let settings = aiSettingsStore.settings
        return try await AiRecipeParser.fromText(text) { messages in
            try await AiClient.chat(
                settings: settings,
                messages: messages,
                responseFormat: ["type": .string("json_object")]
            )
        }
    }
}

/// `Identifiable` route wrapping the parsed `RecipeDraft` so it can drive
/// `.sheet(item:)` (the transient `RecipeDraft` has no id of its own). Mirrors the
/// 清冰箱 generator's `GeneratedDraftRoute`.
private struct ParsedDraftRoute: Identifiable {
    let id = UUID()
    let draft: RecipeDraft
}

/// Dimmed busy overlay shown while OCR + AI structuring runs — blocks interaction
/// and signals progress (mirrors `ImageImportBusyOverlay` / `AiImportBusyOverlay`).
private struct RecipePhotoImportBusyOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
            VStack(spacing: FkSpacing.md) {
                ProgressView()
                    .controlSize(.large)
                Text("识别整理中…")
                    .font(.fkLabelLarge)
                    .foregroundStyle(Color.fkOnSurface)
            }
            .padding(FkSpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                    .fill(Color.fkSurfaceContainerHighest)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("识别整理中")
    }
}

/// A compact inline notice row (icon + message) for surfacing load / OCR / AI
/// errors inside the photo-import sheet.
private struct FkRecipePhotoNotice: View {
    let systemImage: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: FkSpacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.fkDanger)
            Text(message)
                .font(.fkBodyMedium)
                .foregroundStyle(Color.fkOnSurface)
            Spacer(minLength: 0)
        }
        .padding(FkSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous)
                .fill(Color.fkDangerSoft)
        )
    }
}
