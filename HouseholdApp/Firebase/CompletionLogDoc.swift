// CompletionLogDoc.swift
// HouseholdApp
//
// Firestore-backed model for a chore completion event.
// Lives at `/households/{householdId}/completions/{id}`.

import Foundation
import FirebaseFirestore

struct CompletionLogDoc: Identifiable, Codable, Hashable {
    @DocumentID var id: String?

    var choreId: String
    var completedAt: Date
    /// AssignedTo.rawValue (0=Me, 1=Partner). Both isn't logged — each side logs their own.
    var completedBy: Int

    var completedByEnum: AssignedTo {
        AssignedTo(rawValue: Int16(completedBy)) ?? .me
    }
}
