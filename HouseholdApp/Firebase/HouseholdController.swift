// HouseholdController.swift
// HouseholdApp
//
// Manages the current user's household: create, join via invite code, leave.
// The household ID is persisted in UserDefaults so the app remembers which
// household to load on next launch.

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class HouseholdController: ObservableObject {

    // ── Published state ────────────────────────────────────────────────────────
    @Published private(set) var household: HouseholdDoc?
    @Published var errorMessage: String?
    @Published var isBusy: Bool = false

    // Cache the current household ID in UserDefaults across launches.
    private let householdIdKey = "currentHouseholdId"
    private var householdListener: ListenerRegistration?

    private var db: Firestore { Firestore.firestore() }

    var currentHouseholdId: String? {
        UserDefaults.standard.string(forKey: householdIdKey)
    }

    // ── Lifecycle ──────────────────────────────────────────────────────────────
    init() {
        if let id = currentHouseholdId {
            startListening(to: id)
        }
    }

    deinit {
        householdListener?.remove()
    }

    // ── Listen to the current household document ──────────────────────────────
    private func startListening(to householdId: String) {
        householdListener?.remove()
        householdListener = db.collection("households").document(householdId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    if let snapshot = snapshot, snapshot.exists {
                        self.household = try? snapshot.data(as: HouseholdDoc.self)
                    } else {
                        self.household = nil
                    }
                }
            }
    }

    private func setCurrentHousehold(_ id: String) {
        UserDefaults.standard.set(id, forKey: householdIdKey)
        startListening(to: id)
    }

    private func clearCurrentHousehold() {
        UserDefaults.standard.removeObject(forKey: householdIdKey)
        householdListener?.remove()
        household = nil
    }

    // ── Auto-create a personal household (silent, no UI) ──────────────────────
    // Called right after sign-in. If the user already has a household this is
    // a no-op. Creates a household named after the user's display name / email
    // so they land straight in the app without any setup screen.
    func autoCreateIfNeeded() async {
        guard currentHouseholdId == nil,
              let uid = Auth.auth().currentUser?.uid else { return }
        let displayName = Auth.auth().currentUser?.displayName
        await createHousehold(name: displayName)
        _ = uid  // silence unused-variable warning
    }

    // ── Create household ───────────────────────────────────────────────────────
    func createHousehold(name: String?) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Not signed in."
            return
        }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil

        let householdRef = db.collection("households").document()
        let inviteCode = Self.generateInviteCode()
        let doc = HouseholdDoc(
            id: nil,
            name: name?.isEmpty == false ? name : nil,
            inviteCode: inviteCode,
            memberIds: [uid],
            ownerId: uid,
            createdAt: Date()
        )

        do {
            let batch = db.batch()
            try batch.setData(from: doc, forDocument: householdRef)
            batch.setData([
                "householdId": householdRef.documentID,
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: db.collection("invites").document(inviteCode))
            try await batch.commit()
            setCurrentHousehold(householdRef.documentID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // ── Join household via invite code ─────────────────────────────────────────
    func joinHousehold(code: String) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "Not signed in."
            return
        }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else {
            errorMessage = "Please enter an invite code."
            return
        }

        isBusy = true
        defer { isBusy = false }
        errorMessage = nil

        do {
            let inviteSnap = try await db.collection("invites").document(normalized).getDocument()
            guard let householdId = inviteSnap.data()?["householdId"] as? String else {
                errorMessage = "Invite code not found."
                return
            }
            // Add this user to the household's member list.
            try await db.collection("households").document(householdId).updateData([
                "memberIds": FieldValue.arrayUnion([uid])
            ])
            setCurrentHousehold(householdId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // ── Leave household ────────────────────────────────────────────────────────
    // If the leaving user is the last member, the entire household is deleted
    // (household doc, invite doc, and all subcollection documents).
    func leaveHousehold() async {
        guard let uid = Auth.auth().currentUser?.uid,
              let id = currentHouseholdId,
              let current = household else { return }
        isBusy = true
        defer { isBusy = false }

        let remainingMembers = current.memberIds.filter { $0 != uid }

        do {
            if remainingMembers.isEmpty {
                // Last member leaving — delete everything.
                try await deleteHousehold(id: id, inviteCode: current.inviteCode)
            } else {
                // Others remain — just remove ourselves.
                try await db.collection("households").document(id).updateData([
                    "memberIds": FieldValue.arrayRemove([uid])
                ])
            }
            clearCurrentHousehold()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // ── Delete a household and all its data ───────────────────────────────────
    private func deleteHousehold(id: String, inviteCode: String) async throws {
        let householdRef = db.collection("households").document(id)
        let subcollections = ["chores", "categories", "completions", "shoppingItems"]

        // Delete all subcollection documents first (Firestore doesn't cascade).
        for sub in subcollections {
            let docs = try await householdRef.collection(sub).getDocuments()
            if !docs.documents.isEmpty {
                let batch = db.batch()
                docs.documents.forEach { batch.deleteDocument($0.reference) }
                try await batch.commit()
            }
        }

        // Delete invite + household in one batch.
        let batch = db.batch()
        batch.deleteDocument(db.collection("invites").document(inviteCode))
        batch.deleteDocument(householdRef)
        try await batch.commit()
    }

    // ── Rotate invite code (optional future feature) ──────────────────────────
    func rotateInviteCode() async {
        guard let id = currentHouseholdId,
              let oldCode = household?.inviteCode else { return }
        let newCode = Self.generateInviteCode()
        do {
            let batch = db.batch()
            batch.updateData(["inviteCode": newCode],
                             forDocument: db.collection("households").document(id))
            batch.deleteDocument(db.collection("invites").document(oldCode))
            batch.setData([
                "householdId": id,
                "createdAt": FieldValue.serverTimestamp()
            ], forDocument: db.collection("invites").document(newCode))
            try await batch.commit()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // ── Invite code generator ─────────────────────────────────────────────────
    private static func generateInviteCode(length: Int = 6) -> String {
        // Exclude ambiguous characters (0, O, 1, I, L).
        let charset = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<length).map { _ in charset.randomElement()! })
    }
}
