// ChoreStore.swift
// HouseholdApp
//
// Observable wrapper around the Firestore chores collection for the active
// household. Views observe `chores` directly; CRUD goes through the methods.

import Foundation
import FirebaseFirestore

@MainActor
final class ChoreStore: ObservableObject {
    @Published private(set) var chores: [ChoreDoc] = []
    @Published var errorMessage: String?

    private var listener: ListenerRegistration?
    private var householdId: String?
    private var db: Firestore { Firestore.firestore() }

    // ── Lifecycle ──────────────────────────────────────────────────────────────
    /// Call whenever the active household changes (incl. on sign-in).
    func attach(householdId: String?) {
        // Same household? no-op.
        if householdId == self.householdId { return }
        self.householdId = householdId

        listener?.remove()
        chores = []
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
                    self.chores = snapshot?.documents.compactMap {
                        try? $0.data(as: ChoreDoc.self)
                    } ?? []
                }
            }
    }

    deinit { listener?.remove() }

    private func collection(for householdId: String) -> CollectionReference {
        db.collection("households").document(householdId).collection("chores")
    }

    // ── Queries ────────────────────────────────────────────────────────────────
    func chore(withId id: String) -> ChoreDoc? {
        chores.first { $0.id == id }
    }

    // ── CRUD ───────────────────────────────────────────────────────────────────
    func save(_ chore: ChoreDoc) async {
        guard let householdId else { return }
        var toSave = chore
        let col = collection(for: householdId)
        do {
            if let id = toSave.id {
                try col.document(id).setData(from: toSave, merge: true)
            } else {
                toSave.id = nil
                _ = try col.addDocument(from: toSave)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ chore: ChoreDoc) async {
        guard let householdId, let id = chore.id else { return }
        do {
            try await collection(for: householdId).document(id).delete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Toggles the chore's completion. If it has a repeat interval, resets
    /// `isCompleted` to false and advances `dueDate` by the interval.
    func toggleComplete(_ chore: ChoreDoc, by assignee: AssignedTo) async {
        var updated = chore
        let now = Date()

        if chore.isCompleted {
            // Un-complete.
            updated.isCompleted = false
            updated.completedAt = nil
            updated.completedByMe = false
            updated.completedByPartner = false
        } else {
            // Mark complete.
            updated.completedAt = now
            if assignee == .me { updated.completedByMe = true }
            if assignee == .partner { updated.completedByPartner = true }
            if assignee == .both {
                updated.completedByMe = true
                updated.completedByPartner = true
            }

            // If repeating, roll forward instead of archiving.
            if let nextDue = chore.repeatIntervalEnum.nextDate(from: now) {
                updated.isCompleted = false
                updated.dueDate = nextDue
                updated.completedByMe = false
                updated.completedByPartner = false
                // Still fire-and-forget a completion log below.
            } else {
                updated.isCompleted = true
            }
        }

        await save(updated)

        // Append a completion log for history (non-blocking).
        if !chore.isCompleted, let householdId, let choreId = chore.id {
            let log = CompletionLogDoc(
                id: nil,
                choreId: choreId,
                completedAt: now,
                completedBy: Int((assignee == .both ? AssignedTo.me : assignee).rawValue)
            )
            _ = try? db.collection("households").document(householdId)
                .collection("completions").addDocument(from: log)
        }
    }
}
