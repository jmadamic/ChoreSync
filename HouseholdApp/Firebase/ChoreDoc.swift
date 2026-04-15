// ChoreDoc.swift
// HouseholdApp
//
// Firestore-backed model for a chore. Replaces the Core Data `Chore` entity.
// Lives at `/households/{householdId}/chores/{id}`.

import Foundation
import FirebaseFirestore

struct ChoreDoc: Identifiable, Codable, Hashable {
    @DocumentID var id: String?

    var title: String
    var notes: String?

    /// AssignedTo.rawValue  (0=Me, 1=Partner, 2=Both)
    var assignedTo: Int

    /// DueDateType.rawValue (0=specific, 1=week, 2=month, 3=none)
    var dueDateType: Int
    var dueDate: Date?

    /// RepeatInterval.rawValue (0=none, 1=daily, 2=weekly, 3=biweekly, 4=monthly, 5=yearly)
    var repeatInterval: Int

    var isCompleted: Bool
    var completedAt: Date?
    var completedByMe: Bool
    var completedByPartner: Bool

    var createdAt: Date
    var sortOrder: Int

    /// Firestore document ID of the category (nil = uncategorized).
    var categoryId: String?

    // ── Typed enum helpers ─────────────────────────────────────────────────────
    var assignedToEnum: AssignedTo {
        get { AssignedTo(rawValue: Int16(assignedTo)) ?? .both }
        set { assignedTo = Int(newValue.rawValue) }
    }

    var dueDateTypeEnum: DueDateType {
        get { DueDateType(rawValue: Int16(dueDateType)) ?? .none }
        set { dueDateType = Int(newValue.rawValue) }
    }

    var repeatIntervalEnum: RepeatInterval {
        get { RepeatInterval(rawValue: Int16(repeatInterval)) ?? .none }
        set { repeatInterval = Int(newValue.rawValue) }
    }

    // ── Factory ────────────────────────────────────────────────────────────────
    static func new(title: String = "") -> ChoreDoc {
        ChoreDoc(
            title: title,
            notes: nil,
            assignedTo: Int(AssignedTo.both.rawValue),
            dueDateType: Int(DueDateType.none.rawValue),
            dueDate: nil,
            repeatInterval: Int(RepeatInterval.none.rawValue),
            isCompleted: false,
            completedAt: nil,
            completedByMe: false,
            completedByPartner: false,
            createdAt: Date(),
            sortOrder: 0,
            categoryId: nil
        )
    }
}
