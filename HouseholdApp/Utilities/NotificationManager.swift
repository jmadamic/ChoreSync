// NotificationManager.swift
// Schedules and cancels local due-date reminders for chores.
//
// Notification IDs follow the pattern:  hh-chore-{choreId}-{index}
//   index 0 = day-of / period-start reminder
//   index 1 = day-before reminder (specificDate only)
//
// All methods are @MainActor-safe and may be called freely from ChoreStore.

import Foundation
import UserNotifications

@MainActor
final class NotificationManager {

    static let shared = NotificationManager()
    private init() {}

    private let center = UNUserNotificationCenter.current()
    private let idPrefix = "hh-chore-"

    // MARK: - Permission

    /// Asks for notification permission the first time, no-ops if already determined.
    func requestPermissionIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: - Bulk reschedule (after remote sync)

    /// Removes every pending household notification and rebuilds from the current chore list.
    /// Call this after a Firestore snapshot so remote changes (e.g. wife completing a chore)
    /// are reflected in the local notification queue.
    func rescheduleAll(_ chores: [ChoreDoc]) {
        center.removeAllPendingNotificationRequests()
        for chore in chores where !chore.isCompleted {
            addRequests(for: chore)
        }
    }

    // MARK: - Individual schedule / cancel

    /// Schedules (or replaces) the notifications for one chore.
    /// Safe to call after every save — it cancels old entries before adding new ones.
    func schedule(_ chore: ChoreDoc) {
        cancel(choreId: chore.id)
        guard !chore.isCompleted else { return }
        addRequests(for: chore)
    }

    /// Removes all pending notifications for a single chore.
    func cancel(choreId: String) {
        center.removePendingNotificationRequests(withIdentifiers: pendingIds(for: choreId))
    }

    // MARK: - Private

    private func pendingIds(for choreId: String) -> [String] {
        (0..<2).map { "\(idPrefix)\(choreId)-\($0)" }
    }

    private func addRequests(for chore: ChoreDoc) {
        let cal = Calendar.current
        let now  = Date()

        // Build (fireDate, body, index) tuples based on due-date type
        var entries: [(date: Date, body: String, idx: Int)] = []

        switch chore.dueDateTypeEnum {

        case .specificDate:
            guard let due = chore.dueDate else { return }
            // 9am on the due date
            if let dayOf = cal.date(bySettingHour: 9, minute: 0, second: 0, of: due), dayOf > now {
                entries.append((dayOf, "Due today", 0))
            }
            // 9am the day before
            if let prev = cal.date(byAdding: .day, value: -1, to: due),
               let eve  = cal.date(bySettingHour: 9, minute: 0, second: 0, of: prev),
               eve > now {
                entries.append((eve, "Due tomorrow", 1))
            }

        case .week:
            guard let due   = chore.dueDate,
                  let start = cal.dateInterval(of: .weekOfYear, for: due)?.start,
                  let fire  = cal.date(bySettingHour: 9, minute: 0, second: 0, of: start),
                  fire > now
            else { return }
            entries.append((fire, "Due this week", 0))

        case .month:
            guard let due   = chore.dueDate,
                  let start = cal.dateInterval(of: .month, for: due)?.start,
                  let fire  = cal.date(bySettingHour: 9, minute: 0, second: 0, of: start),
                  fire > now
            else { return }
            entries.append((fire, "Due this month", 0))

        case .none:
            return
        }

        for entry in entries {
            let content        = UNMutableNotificationContent()
            content.title      = chore.titleSafe
            content.body       = entry.body
            content.sound      = .default
            content.userInfo   = ["choreId": chore.id]

            let comps   = cal.dateComponents([.year, .month, .day, .hour, .minute], from: entry.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let id      = "\(idPrefix)\(chore.id)-\(entry.idx)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

            center.add(request) { if let error = $0 { print("[Notifications] Failed to add \(id): \(error)") } }
        }
    }
}
