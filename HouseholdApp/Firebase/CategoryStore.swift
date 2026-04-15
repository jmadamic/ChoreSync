// CategoryStore.swift
// HouseholdApp
//
// Observable wrapper around the Firestore categories collection.

import Foundation
import FirebaseFirestore

@MainActor
final class CategoryStore: ObservableObject {
    @Published private(set) var categories: [CategoryDoc] = []
    @Published var errorMessage: String?

    private var listener: ListenerRegistration?
    private var householdId: String?
    private var db: Firestore { Firestore.firestore() }

    func attach(householdId: String?) {
        if householdId == self.householdId { return }
        self.householdId = householdId

        listener?.remove()
        categories = []
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
                    self.categories = snapshot?.documents.compactMap {
                        try? $0.data(as: CategoryDoc.self)
                    } ?? []
                }
            }
    }

    deinit { listener?.remove() }

    private func collection(for householdId: String) -> CollectionReference {
        db.collection("households").document(householdId).collection("categories")
    }

    func category(withId id: String?) -> CategoryDoc? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    func save(_ category: CategoryDoc) async {
        guard let householdId else { return }
        do {
            let col = collection(for: householdId)
            if let id = category.id {
                try col.document(id).setData(from: category, merge: true)
            } else {
                _ = try col.addDocument(from: category)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ category: CategoryDoc) async {
        guard let householdId, let id = category.id else { return }
        do {
            // Nullify categoryId on chores that reference this category.
            let choresCol = db.collection("households").document(householdId).collection("chores")
            let choresSnap = try await choresCol.whereField("categoryId", isEqualTo: id).getDocuments()
            let batch = db.batch()
            for choreDoc in choresSnap.documents {
                batch.updateData(["categoryId": FieldValue.delete()], forDocument: choreDoc.reference)
            }
            batch.deleteDocument(collection(for: householdId).document(id))
            try await batch.commit()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
