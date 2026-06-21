import Foundation

/// The single urgency ordering for inventory rows, so the Inventory list, the
/// Dashboard 临期 preview, and the Expiring board can't drift apart (the rule was
/// verbatim-triplicated across their three stores).
///
/// Most-severe state first (expired → urgent → expiringSoon → fresh), then
/// soonest expiry first (a nil expiry sinks last), stable by the row's original
/// index so ties don't reshuffle across reloads.
enum FreshnessSort {
    static func byUrgency(_ list: [Ingredient]) -> [Ingredient] {
        let order: [FreshnessState] = [.expired, .urgent, .expiringSoon, .fresh]
        func rank(_ state: FreshnessState) -> Int { order.firstIndex(of: state) ?? order.count }

        return list.enumerated().sorted { lhs, rhs in
            let lRank = rank(lhs.element.state)
            let rRank = rank(rhs.element.state)
            if lRank != rRank { return lRank < rRank }

            switch (lhs.element.expiryDate, rhs.element.expiryDate) {
            case let (l?, r?) where l != r:
                return l < r
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                return lhs.offset < rhs.offset // stable by source order
            }
        }.map(\.element)
    }
}
