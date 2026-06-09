import SwiftUI

/// The 购物 tab: lists the household's shopping items grouped by canonical food
/// category, with check-off (struck + dimmed, sorted to the bottom),
/// swipe-to-delete, and a toolbar "+" add sheet.
///
/// The view builds its `ShoppingStore` from the injected `AppDependencies` —
/// the reusable pattern every feature view follows. SwiftData is never touched
/// here; all scoping / sorting / persistence lives in the store.
struct ShoppingView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var store: ShoppingStore?

    var body: some View {
        NavigationStack {
            Group {
                if let store {
                    ShoppingContent(store: store)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.fkSurface)
                }
            }
            .navigationTitle("购物清单")
        }
        // Rebuild the store whenever the active household changes (login "" → uuid,
        // switch, or leave) so the visible list re-scopes to the new household
        // rather than keeping the prior scope's stale rows.
        .task(id: dependencies.householdID) {
            let householdID = dependencies.householdID
            #if DEBUG
            // Sample data is for the local-only personal scope only — a real
            // household's rows come from sync, never the seeder.
            if householdID.isEmpty {
                await ShoppingSeeder.seedIfNeeded(
                    repository: dependencies.shoppingRepository,
                    householdID: householdID
                )
            }
            #endif
            let store = ShoppingStore(
                repository: dependencies.shoppingRepository,
                householdID: householdID,
                syncWriter: dependencies.syncWriter
            )
            self.store = store
            await store.load()
        }
        // Remote merge pulse: a household-sync apply bumps dataRevision; reload
        // so the list reflects rows pulled from other household members.
        .onChange(of: dependencies.syncSession.dataRevision) {
            Task { await store?.load() }
        }
    }
}

/// Inner content bound to a live store (split out so the add sheet and row
/// mutations drive a concrete, non-optional store).
private struct ShoppingContent: View {
    let store: ShoppingStore
    @State private var isAddingItem = false

    var body: some View {
        Group {
            if store.isLoading && !store.hasLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.items.isEmpty {
                emptyState
            } else {
                itemList
            }
        }
        .background(Color.fkSurface)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingItem = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加食材")
            }
        }
        .sheet(isPresented: $isAddingItem) {
            ShoppingAddSheet(store: store)
        }
    }

    // MARK: List

    private var itemList: some View {
        List {
            ForEach(store.displaySections, id: \.category) { section in
                Section {
                    ForEach(section.items, id: \.id) { item in
                        ShoppingRow(item: item) {
                            Task { await store.toggleChecked(item) }
                        }
                        .listRowBackground(Color.fkSurfaceContainerLowest)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await store.delete(item) }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text(section.category)
                        .font(.fkLabelMedium)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.fkSurface)
        .refreshable { await store.load() }
    }

    // MARK: Empty state

    private var emptyState: some View {
        FkEmptyState(
            systemImage: "cart",
            title: "购物清单为空",
            message: "点右上角 + 添加需要购买的食材"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One shopping list row: a tappable check circle, category avatar, name, and
/// optional detail (quantity text). Checked → struck-through + dimmed.
private struct ShoppingRow: View {
    let item: ShoppingItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: FkSpacing.md) {
            Button(action: onToggle) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(item.isChecked ? Color.fkPrimary : Color.fkOutline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isChecked ? "取消勾选 \(item.name)" : "勾选 \(item.name)")

            FkCategoryAvatar(
                imageUrl: item.imageUrl ?? "",
                category: item.category,
                size: 40
            )

            VStack(alignment: .leading, spacing: FkSpacing.xs) {
                Text(item.name)
                    .font(.fkTitleMedium)
                    .foregroundStyle(Color.fkOnSurface)
                    .strikethrough(item.isChecked, color: Color.fkOnSurfaceVariant)
                    .lineLimit(1)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.fkBodySmall)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: FkSpacing.sm)
        }
        .padding(.vertical, FkSpacing.xs)
        .opacity(item.isChecked ? 0.45 : 1)
        .contentShape(Rectangle())
    }
}

/// Add-item sheet: name (required), detail (optional), and a category picker
/// that auto-defaults from `FoodKnowledge` as the user types the name.
private struct ShoppingAddSheet: View {
    let store: ShoppingStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var detail = ""
    @State private var category = FoodCategories.other
    @State private var categoryEdited = false
    @State private var isSaving = false

    private var trimmedName: String { name.trimmed }
    private var canSave: Bool { !trimmedName.isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                Section("食材") {
                    TextField("名称（必填）", text: $name)
                        .onChange(of: name) { _, newValue in
                            guard !categoryEdited else { return }
                            category = FoodKnowledge.categoryFor(newValue)
                        }
                    TextField("数量 / 备注（选填，如 2 盒）", text: $detail)
                }
                Section("分类") {
                    Picker("分类", selection: $category) {
                        ForEach(FoodCategories.values, id: \.self) { value in
                            Text(value).tag(value)
                        }
                    }
                    .onChange(of: category) { _, _ in categoryEdited = true }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.fkSurface)
            .navigationTitle("添加食材")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            await store.add(name: trimmedName, detail: detail, category: category)
            isSaving = false
            dismiss()
        }
    }
}
