import Foundation

/// Holds a household-invite deep link captured by `onOpenURL` until the UI can
/// present its preview/accept flow. Ports the Flutter `_handleIncomingInviteLink`
/// capture seam (auth_gate_screen.dart).
///
/// Stores the RAW input string (not the bare token) so the store's
/// `previewInvite`/`acceptInvite` re-parse it through the SAME `InviteToken.fromInput`
/// path as the manual paste — one validation source. A single instance lives on
/// `AppDependencies` and is injected into the environment so `onOpenURL` (the
/// producer) and `RootView` (the consumer) share it.
///
/// SECURITY: `pendingInput` is a bearer token — never log it (mirrors
/// `InviteToken`'s no-log rule).
@Observable
@MainActor
final class InviteRouter {
    /// The captured invite input awaiting presentation; nil when none pending.
    private(set) var pendingInput: String?

    /// Captures `url` IF it parses as an invite, returning whether it was an invite
    /// (so `onOpenURL` can short-circuit) — otherwise leaves state untouched and
    /// returns false so the URL falls through to the auth handler.
    @discardableResult
    func capture(url: URL) -> Bool {
        guard InviteToken.fromInput(url.absoluteString) != nil else { return false }
        pendingInput = url.absoluteString
        return true
    }

    /// Takes and clears the pending input (one-shot consume).
    func consume() -> String? {
        let value = pendingInput
        pendingInput = nil
        return value
    }

    func clear() { pendingInput = nil }

    // MARK: Presentation gate

    /// What the root should do with a captured invite, given the auth mode. The
    /// signed-in path is the existing preview sheet; the other two close the
    /// previously-silent gap (a signed-out / local-only tap produced zero
    /// feedback, reading as a dead link).
    enum GateOutcome: Equatable {
        /// Nothing pending — no action.
        case none
        /// Signed in: the root's `invitePreviewBinding` presents the sheet.
        case presentPreview
        /// Signed out (backend configured): keep the token pending and prompt a
        /// sign-in — the preview sheet auto-presents after login.
        case promptSignIn
        /// Local-only build (no backend): invites can never be processed —
        /// explain and clear the token.
        case unsupported
    }

    /// Pure routing for a pending invite. An unresolved session (the cold-start
    /// Keychain restore still in flight) HOLDS the gate — `.none` keeps the
    /// token pending so the gate re-runs once `restore()` lands, instead of
    /// misreading the pre-restore signed-out state as 「未登录」 and flashing a
    /// wrong 「请先登录」 at an already-signed-in user. Local-only wins over
    /// signed-out (a local-only build has no login to send the user to; it is
    /// also resolved at birth, so the hold never delays its feedback).
    nonisolated static func gateOutcome(
        hasPendingInvite: Bool,
        sessionResolved: Bool,
        isLocalOnly: Bool,
        isSignedIn: Bool
    ) -> GateOutcome {
        guard hasPendingInvite, sessionResolved else { return .none }
        if isLocalOnly { return .unsupported }
        return isSignedIn ? .presentPreview : .promptSignIn
    }
}
