import Foundation

struct ShoppingItemDoc: Codable, Identifiable {
    var id: String
    var name: String
    var quantity: String?
    var store: String?
    var itemType: String?
    var assignedToMembers: [Int]   // empty = everyone
    var isPurchased: Bool
    var purchasedAt: Date?
    var notes: String?
    var sortOrder: Int32
    var createdAt: Date

    var nameSafe: String       { name }
    var storeGroupKey: String  { store?.isEmpty == false ? store! : "No Store" }
    var typeGroupKey: String   { itemType?.isEmpty == false ? itemType! : "Uncategorized" }
    var quantitySafe: String?  { quantity?.isEmpty == true ? nil : quantity }
    var assignedMemberIndices: Set<Int> {
        get { Set(assignedToMembers) }
        set { assignedToMembers = newValue.sorted() }
    }
}
