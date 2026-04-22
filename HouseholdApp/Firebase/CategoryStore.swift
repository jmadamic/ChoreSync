import Foundation
import FirebaseFirestore

@MainActor
final class CategoryStore: ObservableObject {
    @Published private(set) var categories: [CategoryDoc] = []
    @Published var errorMessage: String?

    private var listener: ListenerRegistration?
    private var db: Firestore { Firestore.firestore() }

    static let defaultCategories: [CategoryDoc] = [
        CategoryDoc(id: "cat-kitchen",   name: "Kitchen",    colorHex: "#FF6B6B", iconName: "fork.knife",   sortOrder: 0),
        CategoryDoc(id: "cat-bathroom",  name: "Bathroom",   colorHex: "#4ECDC4", iconName: "shower",       sortOrder: 1),
        CategoryDoc(id: "cat-laundry",   name: "Laundry",    colorHex: "#45B7D1", iconName: "washer.fill",  sortOrder: 2),
        CategoryDoc(id: "cat-outdoor",   name: "Outdoor",    colorHex: "#96CEB4", iconName: "leaf.fill",    sortOrder: 3),
        CategoryDoc(id: "cat-living",    name: "Living Room", colorHex: "#FFEAA7", iconName: "sofa.fill",   sortOrder: 4),
        CategoryDoc(id: "cat-errands",   name: "Errands",    colorHex: "#DDA0DD", iconName: "car.fill",     sortOrder: 5),
    ]

    func startListening(householdId: String) {
        listener?.remove()
        listener = db.collection("households").document(householdId)
            .collection("categories")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error = error { self.errorMessage = error.localizedDescription; return }
                    let docs = (snapshot?.documents ?? []).compactMap {
                        try? $0.data(as: CategoryDoc.self)
                    }.sorted { $0.sortOrder < $1.sortOrder }
                    self.categories = docs
                }
            }
    }

    func stopListening() { listener?.remove(); listener = nil }

    func seedDefaults(householdId: String) {
        // Only seed if no categories exist yet
        let col = db.collection("households").document(householdId).collection("categories")
        col.getDocuments { [weak self] snapshot, _ in
            guard let self else { return }
            guard let snap = snapshot, snap.isEmpty else { return }
            Task { @MainActor in
                for cat in Self.defaultCategories {
                    try? col.document(cat.id).setData(from: cat)
                }
            }
        }
    }

    func save(_ category: CategoryDoc, householdId: String) {
        let ref = db.collection("households").document(householdId)
            .collection("categories").document(category.id)
        try? ref.setData(from: category)
    }

    func delete(_ category: CategoryDoc, householdId: String) {
        db.collection("households").document(householdId)
            .collection("categories").document(category.id).delete()
        // Nullify chores that reference this category
        // (Firestore doesn't cascade, so we handle in the store or ignore — the UI shows "None")
    }
}
