import Foundation

/// Editable state for the cook-time Deduction Review screen: a list of
/// `DeductionProposal`s the user can select/deselect, re-target (pick which
/// inventory batch to draw from), adjust the deduct amount on, or toggle to
/// 跳过, then apply the SELECTED & deductible ones atomically through
/// `DeductionController`. The deduction mirror of `IntakeReviewStore`.
///
/// Rules ported VERBATIM from the Flutter `DeductionReviewNotifier`:
///   - a proposal is DEDUCTIBLE only when `action == .deduct` AND it has a chosen
///     candidate (`inventoryRowIndex == chosenIndex`); a 缺货 (no-candidate) row
///     is never deductible,
///   - `selectedCount` counts only rows that are both selected AND deductible,
///   - toggling a deductible row's action deduct→skip also deselects it; skip→
///     deduct only re-selects when a chosen candidate exists (else it stays a
///     non-deductible skip),
///   - choosing a candidate sets it deduct + selected,
///   - editing the amount coerces a parse-to-≤0 value back to "1" (never apply 0).
@Observable
@MainActor
final class DeductionReviewStore {
    private(set) var proposals: [DeductionProposal]

    private let controller: DeductionController

    init(proposals: [DeductionProposal], controller: DeductionController) {
        self.proposals = proposals
        self.controller = controller
    }

    // MARK: Derived

    /// True when the proposal can actually reduce stock: a deduct action backed by
    /// a chosen candidate. A 缺货 row (no candidates) is never deductible.
    static func isDeductible(_ p: DeductionProposal) -> Bool {
        p.action == .deduct && ProposalApply.chosenCandidate(p) != nil
    }

    var deductibleCount: Int { proposals.filter(Self.isDeductible).count }
    var selectedCount: Int { proposals.filter { $0.selected && Self.isDeductible($0) }.count }
    /// All deductible rows currently selected — drives the 全选/取消全选 affordance.
    var allSelected: Bool {
        let deductible = proposals.filter(Self.isDeductible)
        return !deductible.isEmpty && deductible.allSatisfy(\.selected)
    }
    var canConfirm: Bool { selectedCount > 0 }
    /// No row can ever be deducted (every recipe ingredient is 缺货) — the screen
    /// shows an empty state but still renders the (skip-only) rows for context.
    var hasNoDeductible: Bool { deductibleCount == 0 }

    // MARK: Edits

    /// Selects/deselects a row. A non-deductible row can never be selected (force
    /// false) — mirrors the Flutter notifier's guard.
    func toggleSelected(_ id: String) {
        update(id) { p in
            guard Self.isDeductible(p) else { return p.copyWith(selected: false) }
            return p.copyWith(selected: !p.selected)
        }
    }

    /// Selects/deselects all deductible rows at once.
    func toggleSelectAll() {
        let next = !allSelected
        proposals = proposals.map { p in
            Self.isDeductible(p) ? p.copyWith(selected: next) : p
        }
    }

    /// Flips a row between 扣库存 and 跳过.
    ///   - deduct → skip: also deselect (a skipped row never applies).
    ///   - skip → deduct: only when a chosen candidate exists; then re-select.
    ///     A 缺货 row (no candidate) stays a deselected skip.
    func toggleAction(_ id: String) {
        update(id) { p in
            if p.action == .deduct {
                return p.copyWith(action: .skip, selected: false)
            }
            guard ProposalApply.chosenCandidate(p) != nil else {
                return p.copyWith(action: .skip, selected: false)
            }
            return p.copyWith(action: .deduct, selected: true)
        }
    }

    /// Picks which inventory batch to draw from. A known candidate index sets the
    /// row deduct + selected; an unknown index is ignored.
    func chooseCandidate(_ id: String, _ index: Int) {
        update(id) { p in
            guard p.candidates.contains(where: { $0.inventoryRowIndex == index }) else { return p }
            return p.copyWith(chosenIndex: index, action: .deduct, selected: true)
        }
    }

    /// Edits the deduct amount, trimming and coercing a parse-to-≤0 value back to
    /// "1" so a deduction can never silently apply 0.
    func updateDeductAmount(_ id: String, _ amount: String) {
        update(id) { p in
            let trimmed = amount.trimmed
            let value = Double(trimmed)
            let coerced = (value == nil || value! <= 0) ? "1" : trimmed
            return p.copyWith(deductAmount: coerced)
        }
    }

    // MARK: Apply

    /// Applies only the SELECTED & deductible proposals atomically via
    /// `DeductionController` (which runs the full `ProposalApply` pipeline +
    /// persists inventory + auto-logs consumed departures). Returns the outcome so
    /// the view can show feedback + dismiss.
    func apply() async -> DeductionController.ApplyOutcome {
        await controller.apply(proposals)
    }

    private func update(_ id: String, _ transform: (DeductionProposal) -> DeductionProposal) {
        guard let index = proposals.firstIndex(where: { $0.id == id }) else { return }
        proposals[index] = transform(proposals[index])
    }
}
