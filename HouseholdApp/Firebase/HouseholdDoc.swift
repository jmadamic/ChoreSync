// HouseholdDoc.swift
// HouseholdApp
//
// Firestore-backed model for a household — the top-level "group" that owns
// all chores, categories, completions, and shopping items.
// Lives at `/households/{id}`.

import Foundation
import FirebaseFirestore

struct HouseholdDoc: Identifiable, Codable, Hashable {
    @DocumentID var id: String?

    /// User-friendly name e.g. "The Adamiches". Optional.
    var name: String?

    /// 6-character invite code (uppercase alphanumeric). Rotated on demand.
    var inviteCode: String

    /// Array of Firebase Auth user UIDs who belong to this household.
    /// Firestore security rules grant read/write access to anyone in this list.
    var memberIds: [String]

    /// UID of the user who created the household (initial "owner").
    var ownerId: String

    var createdAt: Date
}

/// A /invites/{code} document maps a short invite code → household ID so that
/// joiners can look up the household without already knowing its document ID.
struct InviteDoc: Identifiable, Codable {
    /// Document ID IS the invite code (uppercase).
    @DocumentID var id: String?
    var householdId: String
    var createdAt: Date
}
