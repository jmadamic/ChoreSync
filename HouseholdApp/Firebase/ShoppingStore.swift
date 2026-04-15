// ShoppingStore.swift
// HouseholdApp
//
// Observable wrapper around the Firestore shopping items collection.

import Foundation
import FirebaseFirestore

@MainActor
final class ShoppingStore: ObservableObject {
    @Published private(set) var items: [ShoppingItemDoc] = []
    @Published var errorMessage: String?

    private var listener: ListenerRegistration?
    private var householdId: String?
    private var db: Firestore { Firestore.firestore() }

    func attach(householdId: String?) {
        if householdId == self.householdId { return }
        self.householdId = householdId

        listener?.remove()
        items = []
        guard let householdId else { return }

        listener = collection(for: householdId)
            .order(by: "sortOrder")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.items = snapshot?.documents.compactMap {
                        try? $0.data(as: ShoppingItemDoc.self)
                    } ?? []
                }
            }
    }

    deinit { listener?.remove() }

    private func collection(for householdId: String) -> CollectionReference {
        db.collection("households").document(householdId).collection("shoppingItems")
    }

    func save(_ item: ShoppingItemDoc) async {
        guard let householdId else { return }
        do {
            let col = collection(for: householdId)
            if let id = item.id {
                try col.document(id).setData(from: item, merge: true)
            } else {
                _ = try col.addDocument(from: item)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ item: ShoppingItemDoc) async {
        guard let householdId, let id = item.id else { return }
        do {
            try await collection(for: householdId).document(id).delete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePurchased(_ item: ShoppingItemDoc) async {
        var updated = item
        updated.isPurchased.toggle()
        updated.purchasedAt = updated.isPurchased ? Date() : nil
        await save(updated)
    }
}
