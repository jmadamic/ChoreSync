// ShoppingItemDoc.swift
// HouseholdApp
//
// Firestore-backed model for a shopping list item.
// Lives at `/households/{householdId}/shoppingItems/{id}`.

import Foundation
import FirebaseFirestore

struct ShoppingItemDoc: Identifiable, Codable, Hashable {
    @DocumentID var id: String?

    var name: String
    var quantity: String?
    var store: String?
    var itemType: String?

    /// AssignedTo.rawValue (0=Me, 1=Partner, 2=Both)
    var assignedTo: Int

    var isPurchased: Bool
    var purchasedAt: Date?
    var createdAt: Date
    var sortOrder: Int
    var notes: String?

    var assignedToEnum: AssignedTo {
        get { AssignedTo(rawValue: Int16(assignedTo)) ?? .both }
        set { assignedTo = Int(newValue.rawValue) }
    }

    static func new(name: String = "") -> ShoppingItemDoc {
        ShoppingItemDoc(
            name: name,
            quantity: nil,
            store: nil,
            itemType: nil,
            assignedTo: Int(AssignedTo.both.rawValue),
            isPurchased: false,
            purchasedAt: nil,
            createdAt: Date(),
            sortOrder: 0,
            notes: nil
        )
    }
}
