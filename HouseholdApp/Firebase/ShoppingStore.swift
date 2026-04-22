import Foundation
import FirebaseFirestore

@MainActor
final class ShoppingStore: ObservableObject {
    @Published private(set) var items: [ShoppingItemDoc] = []
    @Published var errorMessage: String?

    private var listener: ListenerRegistration?
    private var db: Firestore { Firestore.firestore() }

    func startListening(householdId: String) {
        listener?.remove()
        listener = db.collection("households").document(householdId)
            .collection("shoppingItems")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error = error { self.errorMessage = error.localizedDescription; return }
                    self.items = (snapshot?.documents ?? []).compactMap {
                        try? $0.data(as: ShoppingItemDoc.self)
                    }.sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
                }
            }
    }

    func stopListening() { listener?.remove(); listener = nil }

    func save(_ item: ShoppingItemDoc, householdId: String) {
        let ref = db.collection("households").document(householdId)
            .collection("shoppingItems").document(item.id)
        try? ref.setData(from: item)
    }

    func delete(_ item: ShoppingItemDoc, householdId: String) {
        db.collection("households").document(householdId)
            .collection("shoppingItems").document(item.id).delete()
    }

    func markPurchased(_ item: ShoppingItemDoc, householdId: String) {
        var updated = item
        updated.isPurchased = true
        updated.purchasedAt = Date()
        save(updated, householdId: householdId)
    }

    func markUnpurchased(_ item: ShoppingItemDoc, householdId: String) {
        var updated = item
        updated.isPurchased = false
        updated.purchasedAt = nil
        save(updated, householdId: householdId)
    }
}
