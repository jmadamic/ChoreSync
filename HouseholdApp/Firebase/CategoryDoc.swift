// CategoryDoc.swift
// HouseholdApp
//
// Firestore-backed model for a chore category.
// Lives at `/households/{householdId}/categories/{id}`.

import Foundation
import FirebaseFirestore

struct CategoryDoc: Identifiable, Codable, Hashable {
    @DocumentID var id: String?

    var name: String
    /// Hex color string e.g. "#FF6B6B"
    var colorHex: String
    /// SF Symbol name e.g. "fork.knife"
    var iconName: String
    var sortOrder: Int

    static func new(name: String = "", colorHex: String = "#007AFF", iconName: String = "square.grid.2x2") -> CategoryDoc {
        CategoryDoc(name: name, colorHex: colorHex, iconName: iconName, sortOrder: 0)
    }
}
