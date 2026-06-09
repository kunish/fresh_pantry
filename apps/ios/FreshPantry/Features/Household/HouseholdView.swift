import SwiftUI

/// The 家庭共享 management screen, pushed from Settings. The activation surface for
/// the whole sync engine: creating / joining / switching a household sets
/// `SyncSession.selectedHouseholdId`, which the root `.task(id:)` turns into a
/// content pull + the writer's enqueue scope.
///
/// Builds its `HouseholdSessionStore` in `.task` from the injected
/// `AppDependencies` (the established store pattern), then renders one of four
/// states off `AuthService.state` + the store:
/// - local-only (no backend) → a graceful "未配置后端" empty state;
/// - signed out → a sign-in prompt with a `LoginView` link;
/// - signed in, no households → a create + join form;
/// - in a household → current household, members, invite, switch, leave/dissolve.
struct HouseholdView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var store: HouseholdSessionStore?

    var body: some View {
        Group {
            if let store {
                HouseholdContent(store: store, auth: dependencies.authService)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.fkSurface)
            }
        }
        .navigationTitle("家庭共享")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.fkSurface)
        .tint(.fkPrimary)
        .task {
            if store == nil {
                let store = HouseholdSessionStore(
                    remote: dependencies.remotePantryRepository,
                    session: dependencies.syncSession,
                    auth: dependencies.authService,
                    inventory: dependencies.inventoryRepository,
                    shopping: dependencies.shoppingRepository,
                    customRecipe: dependencies.customRecipeRepository,
                    mealPlan: dependencies.mealPlanRepository
                )
                self.store = store
                await store.refreshHouseholds()
            }
        }
    }
}

/// Inner content bound to the live `@Observable` store + auth (split out so direct
/// observation drives the body the way the other feature views do).
private struct HouseholdContent: View {
    let store: HouseholdSessionStore
    @Bindable var auth: AuthService

    var body: some View {
        ScrollView {
            VStack(spacing: FkSpacing.xl) {
                content
                if let errorMessage = store.errorMessage {
                    errorBanner(errorMessage)
                }
            }
            .padding(FkSpacing.lg)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color.fkSurface)
        .refreshable { await store.refreshHouseholds() }
    }

    // MARK: State routing

    @ViewBuilder
    private var content: some View {
        if !store.isConfigured || auth.state == .localOnly {
            localOnlyState
        } else if auth.signedInEmail == nil {
            signedOutState
        } else if store.selectedHousehold == nil {
            OnboardHouseholdSection(store: store)
        } else {
            ActiveHouseholdSection(store: store, auth: auth)
        }
    }

    // MARK: Local-only

    private var localOnlyState: some View {
        FkEmptyState(
            systemImage: "wifi.slash",
            title: "本地模式",
            message: "此版本未配置 Supabase 后端,家庭共享不可用。库存、采购与食谱仍可在本机正常使用。"
        )
    }

    // MARK: Signed out

    private var signedOutState: some View {
        VStack(spacing: FkSpacing.lg) {
            FkEmptyState(
                systemImage: "person.crop.circle.badge.exclamationmark",
                title: "请先登录",
                message: "登录后即可创建或加入家庭,在成员间同步库存、采购与食谱。"
            )
            NavigationLink {
                LoginView(auth: auth)
            } label: {
                Label("前往登录", systemImage: "arrow.right.circle")
                    .font(.fkLabelLarge)
                    .foregroundStyle(Color.fkOnPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.fkPrimary))
            }
            .buttonStyle(.fkPressable)
        }
    }

    // MARK: Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: FkSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.fkDanger)
            Text(message)
                .font(.fkBodySmall)
                .foregroundStyle(Color.fkDanger)
            Spacer(minLength: 0)
        }
        .padding(FkSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.sm, style: .continuous)
                .fill(Color.fkDangerSoft)
        )
    }
}

// MARK: - Onboard (no household yet)

/// Shown when the signed-in user belongs to no household: a create form + a join
/// form (paste invite → preview stats → accept).
private struct OnboardHouseholdSection: View {
    let store: HouseholdSessionStore

    @State private var newName = ""
    @State private var inviteInput = ""

    var body: some View {
        VStack(spacing: FkSpacing.xl) {
            if !store.pendingInvitePreviews.isEmpty {
                IncomingInvitesCard(store: store)
            }
            createCard
            joinCard
        }
    }

    private var createCard: some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.lg) {
                FkSectionHeader(title: "创建家庭")
                Text("创建后,本机现有的库存、采购与食谱会成为这个家庭的初始数据。")
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
                FkFormField(label: "家庭名称") {
                    FkTextFieldPill(text: $newName, placeholder: "例如:我的家")
                }
                primaryButton(title: "创建", busyTitle: "创建中…", systemImage: "house") {
                    Task {
                        await store.createHousehold(name: newName)
                        if store.errorMessage == nil { newName = "" }
                    }
                }
                .disabled(store.isSubmitting || newName.trimmed.isEmpty)
            }
        }
    }

    private var joinCard: some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.lg) {
                FkSectionHeader(title: "加入家庭")
                Text("粘贴邀请链接或邀请码,确认信息后即可加入。")
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
                FkFormField(label: "邀请链接 / 邀请码") {
                    FkTextFieldPill(text: $inviteInput, placeholder: "粘贴邀请链接或邀请码")
                }
                HStack(spacing: FkSpacing.md) {
                    secondaryButton(title: "预览", systemImage: "eye") {
                        Task { await store.previewInvite(input: inviteInput) }
                    }
                    .disabled(store.isSubmitting || inviteInput.trimmed.isEmpty)
                }
                if let preview = store.invitePreview {
                    InvitePreviewCard(preview: preview)
                    primaryButton(title: "接受邀请", busyTitle: "加入中…", systemImage: "person.badge.plus") {
                        Task {
                            await store.acceptInvite(input: inviteInput)
                            if store.errorMessage == nil { inviteInput = "" }
                        }
                    }
                    .disabled(store.isSubmitting)
                }
            }
        }
    }

    private func primaryButton(title: String, busyTitle: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: FkSpacing.sm) {
                if store.isSubmitting {
                    ProgressView().tint(Color.fkOnPrimary)
                } else {
                    Image(systemName: systemImage)
                }
                Text(store.isSubmitting ? busyTitle : title)
            }
            .font(.fkLabelLarge)
            .foregroundStyle(Color.fkOnPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Capsule().fill(store.isSubmitting ? Color.fkOutlineVariant : Color.fkPrimary))
        }
        .buttonStyle(.fkPressable)
    }

    private func secondaryButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.fkLabelLarge)
                .foregroundStyle(Color.fkPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.fkPrimarySoft))
        }
        .buttonStyle(.fkPressable)
    }
}

// MARK: - Active household

/// Shown when the user is in a household: the current household (with rename), the
/// member list (owner can remove + invite), a switcher when multiple, and the
/// leave / dissolve actions.
private struct ActiveHouseholdSection: View {
    let store: HouseholdSessionStore
    @Bindable var auth: AuthService

    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var inviteEmail = ""
    @State private var shareURL: String?
    @State private var memberToRemove: HouseholdMember?
    @State private var showDissolveConfirm = false
    @State private var showLeaveConfirm = false
    @State private var inviteToRevoke: OwnerPendingInvite?

    private var isOwner: Bool { store.isOwnerOfSelected }

    var body: some View {
        VStack(spacing: FkSpacing.xl) {
            if !store.pendingInvitePreviews.isEmpty {
                IncomingInvitesCard(store: store)
            }
            householdCard
            if store.households.count > 1 {
                switcherCard
            }
            membersCard
            inviteCard
            if isOwner, !store.ownerPendingInvites.isEmpty {
                ownerPendingInvitesCard
            }
            dangerCard
        }
        .alert("移除成员", isPresented: removeMemberBinding, presenting: memberToRemove) { member in
            Button("移除", role: .destructive) {
                Task { await store.removeMember(member.userId) }
            }
            Button("取消", role: .cancel) {}
        } message: { member in
            Text("确定将 \(member.email.isEmpty ? "该成员" : member.email) 从家庭中移除吗?")
        }
        .confirmationDialog("解散家庭", isPresented: $showDissolveConfirm, titleVisibility: .visible) {
            Button("解散家庭", role: .destructive) {
                Task { await store.dissolveHousehold() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("解散后,该家庭的所有共享数据将被删除,且无法恢复。")
        }
        .confirmationDialog("离开家庭", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
            Button("离开家庭", role: .destructive) {
                Task { await store.leaveHousehold() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("离开后,你将不再看到该家庭的共享数据。")
        }
        .confirmationDialog("撤销邀请", isPresented: revokeInviteBinding, presenting: inviteToRevoke) { invite in
            Button("撤销邀请", role: .destructive) {
                Task { await store.revokeInvite(householdId: store.selectedHouseholdId, inviteId: invite.id) }
            }
            Button("取消", role: .cancel) {}
        } message: { invite in
            Text("确定撤销发给 \(invite.email.isEmpty ? "该邮箱" : invite.email) 的邀请吗?")
        }
    }

    // MARK: Owner-issued pending invites

    /// "待处理邀请" — open invites the owner has issued, each with a revoke action.
    /// Owner-gated by the caller (`isOwner && !ownerPendingInvites.isEmpty`).
    private var ownerPendingInvitesCard: some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.md) {
                FkSectionHeader(title: "待处理邀请", count: store.ownerPendingInvites.count)
                ForEach(store.ownerPendingInvites, id: \.id) { invite in
                    HStack(spacing: FkSpacing.md) {
                        Image(systemName: "envelope.badge.clock")
                            .foregroundStyle(Color.fkPrimary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(invite.email.isEmpty ? "开放邀请" : invite.email)
                                .font(.fkBodyMedium)
                                .foregroundStyle(Color.fkOnSurface)
                            Text("待接受")
                                .font(.fkLabelSmall)
                                .foregroundStyle(Color.fkOnSurfaceVariant)
                        }
                        Spacer(minLength: 0)
                        Button {
                            inviteToRevoke = invite
                        } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(Color.fkDanger)
                        }
                        .buttonStyle(.fkPressable)
                        .disabled(store.isSubmitting)
                        .accessibilityLabel("撤销邀请")
                    }
                }
            }
        }
    }

    // MARK: Current household + rename

    private var householdCard: some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.md) {
                Text("当前家庭")
                    .font(.fkLabelSmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
                if isRenaming {
                    FkTextFieldPill(text: $renameText, placeholder: "家庭名称")
                    HStack(spacing: FkSpacing.md) {
                        Button("保存") {
                            Task {
                                await store.updateHouseholdName(renameText)
                                if store.errorMessage == nil { isRenaming = false }
                            }
                        }
                        .font(.fkLabelLarge)
                        .foregroundStyle(Color.fkPrimary)
                        .buttonStyle(.fkPressable)
                        .disabled(store.isSubmitting || renameText.trimmed.isEmpty)
                        Button("取消") { isRenaming = false }
                            .font(.fkLabelLarge)
                            .foregroundStyle(Color.fkOnSurfaceVariant)
                            .buttonStyle(.fkPressable)
                    }
                } else {
                    HStack(spacing: FkSpacing.sm) {
                        Image(systemName: "house.fill")
                            .foregroundStyle(Color.fkPrimary)
                        Text(store.selectedHousehold?.name ?? "")
                            .font(.fkTitleMedium)
                            .foregroundStyle(Color.fkOnSurface)
                        Spacer(minLength: 0)
                        if isOwner {
                            Button {
                                renameText = store.selectedHousehold?.name ?? ""
                                isRenaming = true
                            } label: {
                                Label("重命名", systemImage: "pencil")
                                    .font(.fkLabelMedium)
                                    .foregroundStyle(Color.fkPrimary)
                            }
                            .buttonStyle(.fkPressable)
                        }
                    }
                }
            }
        }
    }

    // MARK: Switcher (multiple households)

    private var switcherCard: some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.md) {
                FkSectionHeader(title: "切换家庭")
                ForEach(store.households, id: \.id) { household in
                    Button {
                        Task { await store.switchHousehold(household.id) }
                    } label: {
                        HStack(spacing: FkSpacing.sm) {
                            Image(systemName: household.id == store.selectedHouseholdId
                                ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(household.id == store.selectedHouseholdId
                                    ? Color.fkPrimary : Color.fkOutline)
                            Text(household.name)
                                .font(.fkBodyMedium)
                                .foregroundStyle(Color.fkOnSurface)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.fkPressable)
                    .disabled(store.isLoading)
                }
            }
        }
    }

    // MARK: Members

    private var membersCard: some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.md) {
                FkSectionHeader(title: "成员", count: store.members.count)
                if store.members.isEmpty {
                    Text("暂无成员信息")
                        .font(.fkBodySmall)
                        .foregroundStyle(Color.fkOnSurfaceVariant)
                } else {
                    ForEach(store.members, id: \.userId) { member in
                        memberRow(member)
                    }
                }
            }
        }
    }

    private func memberRow(_ member: HouseholdMember) -> some View {
        HStack(spacing: FkSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.fkPrimarySoft)
                    .frame(width: 36, height: 36)
                Text(member.email.first.map { String($0).uppercased() } ?? "?")
                    .font(.fkLabelLarge)
                    .foregroundStyle(Color.fkPrimary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(member.email.isEmpty ? "成员" : member.email)
                    .font(.fkBodyMedium)
                    .foregroundStyle(Color.fkOnSurface)
                Text(member.role == "owner" ? "所有者" : "成员")
                    .font(.fkLabelSmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
            Spacer(minLength: 0)
            // Owner can remove other members (never themselves — leaving/dissolving
            // is the owner's own exit path).
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

    // MARK: Invite

    private var inviteCard: some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.md) {
                FkSectionHeader(title: "邀请成员")
                Text("可选填邀请对象的邮箱;留空则生成一个开放邀请链接。")
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
                FkTextFieldPill(text: $inviteEmail, placeholder: "对方邮箱(可选)", keyboard: .emailAddress)
                Button {
                    Task { shareURL = await store.createInvite(email: inviteEmail) }
                } label: {
                    HStack(spacing: FkSpacing.sm) {
                        if store.isSubmitting {
                            ProgressView().tint(Color.fkOnPrimary)
                        } else {
                            Image(systemName: "envelope.badge")
                        }
                        Text(store.isSubmitting ? "生成中…" : "生成邀请链接")
                    }
                    .font(.fkLabelLarge)
                    .foregroundStyle(Color.fkOnPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(store.isSubmitting ? Color.fkOutlineVariant : Color.fkPrimary))
                }
                .buttonStyle(.fkPressable)
                .disabled(store.isSubmitting)

                if let shareURL {
                    shareResult(shareURL)
                }
            }
        }
    }

    private func shareResult(_ url: String) -> some View {
        let qr = QRCodeGenerator.image(from: url)
        return VStack(alignment: .leading, spacing: FkSpacing.md) {
            // Scannable QR on a white card (family members can scan to join).
            if let qr {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(FkSpacing.lg)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous).fill(.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: FkRadius.lg, style: .continuous)
                            .stroke(Color.fkOutlineVariant)
                    )
            }
            Text("邀请链接")
                .font(.fkLabelSmall)
                .foregroundStyle(Color.fkOnSurfaceVariant)
            Text(url)
                .font(.fkBodySmall)
                .foregroundStyle(Color.fkOnSurface)
                .textSelection(.enabled)
                .lineLimit(2)
            HStack(spacing: FkSpacing.lg) {
                Button {
                    UIPasteboard.general.string = url
                } label: {
                    Label("复制链接", systemImage: "doc.on.doc")
                        .font(.fkLabelMedium)
                        .foregroundStyle(Color.fkPrimary)
                }
                .buttonStyle(.fkPressable)
                ShareLink(item: url) {
                    Label("分享链接", systemImage: "square.and.arrow.up")
                        .font(.fkLabelMedium)
                        .foregroundStyle(Color.fkPrimary)
                }
                .buttonStyle(.fkPressable)
                if let qr {
                    ShareLink(
                        item: InviteQRImage(image: qr),
                        preview: SharePreview("家庭邀请二维码", image: Image(uiImage: qr))
                    ) {
                        Label("分享二维码", systemImage: "qrcode")
                            .font(.fkLabelMedium)
                            .foregroundStyle(Color.fkPrimary)
                    }
                    .buttonStyle(.fkPressable)
                }
            }
        }
        .padding(FkSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous)
                .fill(Color.fkSurfaceContainer)
        )
    }

    // MARK: Leave / dissolve

    private var dangerCard: some View {
        VStack(spacing: FkSpacing.md) {
            if isOwner {
                dangerButton(title: "解散家庭", systemImage: "trash") { showDissolveConfirm = true }
            } else {
                dangerButton(title: "离开家庭", systemImage: "rectangle.portrait.and.arrow.right") {
                    showLeaveConfirm = true
                }
            }
        }
    }

    private func dangerButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.fkLabelLarge)
                .foregroundStyle(Color.fkDanger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color.fkDangerSoft))
        }
        .buttonStyle(.fkPressable)
        .disabled(store.isSubmitting)
    }

    private var removeMemberBinding: Binding<Bool> {
        Binding(
            get: { memberToRemove != nil },
            set: { if !$0 { memberToRemove = nil } }
        )
    }

    private var revokeInviteBinding: Binding<Bool> {
        Binding(
            get: { inviteToRevoke != nil },
            set: { if !$0 { inviteToRevoke = nil } }
        )
    }
}

// MARK: - Invite preview

/// A compact preview of an invite's household + content stats, shown before
/// accepting (mirrors the Flutter join confirmation).
private struct InvitePreviewCard: View {
    let preview: HouseholdInvitePreview

    var body: some View {
        VStack(alignment: .leading, spacing: FkSpacing.sm) {
            Text(preview.householdName.isEmpty ? "家庭" : preview.householdName)
                .font(.fkTitleSmall)
                .foregroundStyle(Color.fkOnSurface)
            if !preview.ownerEmail.isEmpty {
                Text("所有者:\(preview.ownerEmail)")
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
            // Directed invites carry the invited email — surface it so the user can
            // confirm the invite was meant for them (Flutter parity).
            if !preview.invitedEmail.isEmpty {
                Text("邀请邮箱:\(preview.invitedEmail)")
                    .font(.fkBodySmall)
                    .foregroundStyle(Color.fkOnSurfaceVariant)
            }
            HStack(spacing: FkSpacing.lg) {
                stat(count: preview.memberCount, label: "成员")
                stat(count: preview.inventoryCount, label: "库存")
                stat(count: preview.shoppingCount, label: "采购")
                stat(count: preview.customRecipeCount, label: "食谱")
            }
        }
        .padding(FkSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: FkRadius.md, style: .continuous)
                .fill(Color.fkSurfaceContainer)
        )
    }

    private func stat(count: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.fkTitleSmall)
                .foregroundStyle(Color.fkPrimary)
            Text(label)
                .font(.fkLabelSmall)
                .foregroundStyle(Color.fkOnSurfaceVariant)
        }
    }
}

// MARK: - Deep-link invite preview sheet

/// Identifiable route for the root invite-preview sheet (id = the raw input so the
/// sheet identity is stable across re-renders).
struct InvitePreviewRoute: Identifiable {
    var id: String { input }
    let input: String
}

/// Root-presented sheet for a household invite arriving via deep link: previews the
/// invite (reusing `InvitePreviewCard`) and accepts it. Builds its own
/// `HouseholdSessionStore` (the per-screen pattern — all instances drive the SAME
/// injected `SyncSession`, the activation source of truth). On accept success it
/// clears the router and dismisses; the root `.task(id: selectedHouseholdId)` then
/// fires the content pull.
struct InvitePreviewSheet: View {
    let input: String

    @Environment(AppDependencies.self) private var dependencies
    @Environment(InviteRouter.self) private var inviteRouter
    @Environment(\.dismiss) private var dismiss
    @State private var store: HouseholdSessionStore?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FkSpacing.lg) {
                    if let store {
                        body(for: store)
                    } else {
                        ProgressView().padding(.top, FkSpacing.huge)
                    }
                }
                .padding(FkSpacing.lg)
            }
            .background(Color.fkSurface)
            .navigationTitle("家庭邀请")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("稍后处理") { dismiss() }
                }
            }
            .tint(.fkPrimary)
        }
        .presentationDetents([.medium, .large])
        .task {
            if store == nil {
                let store = HouseholdSessionStore(
                    remote: dependencies.remotePantryRepository,
                    session: dependencies.syncSession,
                    auth: dependencies.authService,
                    inventory: dependencies.inventoryRepository,
                    shopping: dependencies.shoppingRepository,
                    customRecipe: dependencies.customRecipeRepository,
                    mealPlan: dependencies.mealPlanRepository
                )
                self.store = store
                await store.previewInvite(input: input)
            }
        }
    }

    @ViewBuilder
    private func body(for store: HouseholdSessionStore) -> some View {
        if let preview = store.invitePreview {
            InvitePreviewCard(preview: preview)
            Button {
                Task {
                    await store.acceptInvite(input: input)
                    if store.errorMessage == nil {
                        inviteRouter.clear()
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: FkSpacing.sm) {
                    if store.isSubmitting {
                        ProgressView().tint(Color.fkOnPrimary)
                    } else {
                        Image(systemName: "person.badge.plus")
                    }
                    Text(store.isSubmitting ? "加入中…" : "接受邀请")
                }
                .font(.fkLabelLarge)
                .foregroundStyle(Color.fkOnPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(store.isSubmitting ? Color.fkOutlineVariant : Color.fkPrimary))
            }
            .buttonStyle(.fkPressable)
            .disabled(store.isSubmitting)
        } else if store.isSubmitting {
            ProgressView().padding(.top, FkSpacing.huge)
        }
        if let errorMessage = store.errorMessage {
            HStack(spacing: FkSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.fkDanger)
                Text(errorMessage).font(.fkBodySmall).foregroundStyle(Color.fkDanger)
                Spacer(minLength: 0)
            }
            .padding(FkSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: FkRadius.sm, style: .continuous).fill(Color.fkDangerSoft))
        }
    }
}

// MARK: - Received invites (one-tap accept)

/// "收到的邀请" — invites addressed to the signed-in user, each shown as a preview
/// card with a one-tap 接受. Rendered in both the onboard and active surfaces when
/// `pendingInvitePreviews` is non-empty (ports the Flutter incoming-invite list).
private struct IncomingInvitesCard: View {
    let store: HouseholdSessionStore

    var body: some View {
        FkCard {
            VStack(alignment: .leading, spacing: FkSpacing.md) {
                FkSectionHeader(title: "收到的邀请", count: store.pendingInvitePreviews.count)
                ForEach(store.pendingInvitePreviews, id: \.inviteId) { preview in
                    VStack(alignment: .leading, spacing: FkSpacing.sm) {
                        InvitePreviewCard(preview: preview)
                        Button {
                            Task { await store.acceptInviteById(preview.inviteId) }
                        } label: {
                            HStack(spacing: FkSpacing.sm) {
                                if store.isSubmitting {
                                    ProgressView().tint(Color.fkOnPrimary)
                                } else {
                                    Image(systemName: "person.badge.plus")
                                }
                                Text(store.isSubmitting ? "加入中…" : "接受邀请")
                            }
                            .font(.fkLabelLarge)
                            .foregroundStyle(Color.fkOnPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(store.isSubmitting ? Color.fkOutlineVariant : Color.fkPrimary))
                        }
                        .buttonStyle(.fkPressable)
                        .disabled(store.isSubmitting)
                    }
                }
            }
        }
    }
}
