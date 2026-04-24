import Foundation
import FirebaseFirestore

@MainActor
final class ChoreStore: ObservableObject {
    @Published private(set) var chores: [ChoreDoc] = []
    @Published var errorMessage: String?

    private var listener: ListenerRegistration?
    private var db: Firestore { Firestore.firestore() }

    func startListening(householdId: String) {
        listener?.remove()
        listener = db.collection("households").document(householdId)
            .collection("chores")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error = error { self.errorMessage = error.localizedDescription; return }
                    self.chores = (snapshot?.documents ?? []).compactMap {
                        try? $0.data(as: ChoreDoc.self)
                    }.sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
                    NotificationManager.shared.rescheduleAll(self.chores)
                }
            }
    }

    func stopListening() { listener?.remove(); listener = nil }

    func save(_ chore: ChoreDoc, householdId: String) {
        let ref = db.collection("households").document(householdId)
            .collection("chores").document(chore.id)
        try? ref.setData(from: chore)
        NotificationManager.shared.schedule(chore)   // immediate local update before snapshot arrives
    }

    func delete(_ chore: ChoreDoc, householdId: String) {
        db.collection("households").document(householdId)
            .collection("chores").document(chore.id).delete()
        NotificationManager.shared.cancel(choreId: chore.id)
    }

    func markComplete(_ chore: ChoreDoc, byMemberIndex memberIndex: Int, householdId: String) {
        var updated = chore
        var indices = Set(updated.completedByMembers)
        indices.insert(memberIndex)
        updated.completedByMembers = indices.sorted()

        let interval = updated.repeatIntervalEnum
        if interval != .none {
            let base = updated.dueDate ?? Date()
            updated.dueDate = interval.nextDate(from: base)
            updated.dueDateType = Int16(DueDateType.specificDate.rawValue)
            updated.isCompleted = false
            updated.completedAt = nil
            updated.completedByMembers = []
        } else {
            updated.isCompleted = true
            updated.completedAt = Date()
        }

        // Log completion
        let log = CompletionLogDoc(
            id: UUID().uuidString,
            choreId: chore.id,
            completedAt: Date(),
            completedByMemberIndex: memberIndex
        )
        let logRef = db.collection("households").document(householdId)
            .collection("completions").document(log.id)
        try? logRef.setData(from: log)

        save(updated, householdId: householdId)
    }

    func markIncomplete(_ chore: ChoreDoc, householdId: String) {
        var updated = chore
        updated.isCompleted = false
        updated.completedAt = nil
        updated.completedByMembers = []
        save(updated, householdId: householdId)
    }
}
