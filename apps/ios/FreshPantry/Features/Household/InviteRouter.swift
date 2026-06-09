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
}
