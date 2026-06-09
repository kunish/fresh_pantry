import Foundation

/// Pure function computing the set of `ScheduledNotification`s from inventory +
/// reminder settings (no I/O). Ported from `lib/services/expiry_scheduler.dart`.
///
/// PARITY-CRITICAL: the notification id is a deterministic 31-multiplier rolling
/// hash over the UTF-16 code units (Dart `codeUnits`) of a fixed field string,
/// masked to a positive int31 so identifiers stay stable across launches. The
/// daily-summary slot reserves id `1`; any per-item hash that collides with it
/// is bumped by one.
enum ExpiryScheduler {
    /// 09:00 local — when reminders fire.
    static let dailySummaryHour = 9
    /// Reserved id for the single recurring daily-summary slot.
    static let dailySummaryId = 1

    /// Builds the full notification set: per-item D-N reminders (in the
    /// settings' largest-first [7,3,1] offset order) plus the optional daily
    /// summary. Slots not strictly after `now` are dropped (already past).
    static func compute(
        inventory: [Ingredient],
        settings: ReminderSettings,
        now: Date,
        calendar: Calendar = .current
    ) -> [ScheduledNotification] {
        var out: [ScheduledNotification] = []

        // Per-item D-N notifications.
        for ing in inventory {
            guard let expiry = ing.expiryDate else { continue }
            let expiryComponents = calendar.dateComponents([.year, .month, .day], from: expiry)
            guard let year = expiryComponents.year,
                  let month = expiryComponents.month,
                  let day = expiryComponents.day
            else { continue }

            for offset in settings.enabledOffsetDays {
                // `day - offset` underflow is normalized by `calendar.date(from:)`,
                // matching Dart `DateTime(y, m, d - offset, 9, 0)`.
                var slot = DateComponents()
                slot.year = year
                slot.month = month
                slot.day = day - offset
                slot.hour = dailySummaryHour
                slot.minute = 0
                guard let scheduledDate = calendar.date(from: slot),
                      scheduledDate > now
                else { continue }

                out.append(ScheduledNotification(
                    id: idFor(ing, offset: offset),
                    title: "\(offset) 天后过期",
                    body: "\(ing.name) \(ing.quantity)\(ing.unit) 还剩 \(offset) 天",
                    scheduledAt: scheduledDate,
                    kind: .expiry
                ))
            }
        }

        // Daily summary — single recurring slot at the next local 09:00.
        if settings.remindDaily {
            var today = calendar.dateComponents([.year, .month, .day], from: now)
            today.hour = dailySummaryHour
            today.minute = 0
            if let today9 = calendar.date(from: today) {
                let next = today9 > now ? today9 : calendar.date(byAdding: .day, value: 1, to: today9) ?? today9
                out.append(ScheduledNotification(
                    id: dailySummaryId,
                    title: "每日临期提醒",
                    body: "查看今天到期 / 已过期食材",
                    scheduledAt: next,
                    kind: .dailySummary
                ))
            }
        }

        return out
    }

    /// Deterministic id from ingredient id + name + storage + addedAt +
    /// expiryDate + offset. Including the id and expiry date prevents two
    /// batches of the same product (added in the same millisecond) from
    /// colliding. The hash is rolled over UTF-16 code units to match Dart's
    /// `String.codeUnits`, masked to a positive int31.
    static func idFor(_ ing: Ingredient, offset: Int) -> Int {
        let addedAtMs = ing.addedAt.map { Int($0.timeIntervalSince1970 * 1000) } ?? 0
        let expiryMs = ing.expiryDate.map { Int($0.timeIntervalSince1970 * 1000) } ?? 0
        let base = "\(ing.id)|\(ing.name)|\(ing.storage.rawValue)|\(addedAtMs)|\(expiryMs)|\(offset)"

        var hash = 0
        for code in base.utf16 {
            hash = (hash &* 31 &+ Int(code)) & 0x7fff_ffff
        }
        if hash == dailySummaryId { hash += 1 } // never collide with the reserved id
        return hash
    }
}
