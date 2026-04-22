// AuthController.swift
// HouseholdApp
//
// Manages Firebase Auth state. Signs in anonymously on first launch so the
// app works immediately with no sign-in screen. When the user wants to sync
// with someone, they upgrade to Google Sign-In — the anonymous account is
// linked so all existing data (household, chores, etc.) is preserved.

import Foundation
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import UIKit

@MainActor
final class AuthController: ObservableObject {

    // ── Published state ────────────────────────────────────────────────────────
    @Published private(set) var user: User?
    @Published var errorMessage: String?

    private var authListener: AuthStateDidChangeListenerHandle?

    init() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.user = user }
        }
        // Sign in anonymously if not already authenticated.
        Task { await self.signInAnonymouslyIfNeeded() }
    }

    deinit {
        if let handle = authListener { Auth.auth().removeStateDidChangeListener(handle) }
    }

    // ── Computed helpers ───────────────────────────────────────────────────────
    var isSignedIn:  Bool    { user != nil }
    var isAnonymous: Bool    { user?.isAnonymous ?? true }
    var uid:         String? { user?.uid }
    var displayName: String? { user?.displayName }
    var email:       String? { user?.email }

    // ── Anonymous sign-in ──────────────────────────────────────────────────────
    private func signInAnonymouslyIfNeeded() async {
        guard Auth.auth().currentUser == nil else { return }
        do {
            try await Auth.auth().signInAnonymously()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // ── Google Sign-In (upgrades anonymous → Google) ──────────────────────────
    // If the user is anonymous, their account is linked to Google so all their
    // existing household data is preserved under the same UID.
    // If linking fails (Google account already exists), falls back to direct sign-in.
    func signInWithGoogle(presenting: UIViewController) async {
        errorMessage = nil
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Firebase is not configured."
            return
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenting)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Google Sign-In returned no ID token."
                return
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )

            if let currentUser = Auth.auth().currentUser, currentUser.isAnonymous {
                // Try to upgrade the anonymous account to Google.
                do {
                    _ = try await currentUser.link(with: credential)
                } catch {
                    // Credential already in use — just sign in directly.
                    _ = try await Auth.auth().signIn(with: credential)
                }
            } else {
                _ = try await Auth.auth().signIn(with: credential)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // ── Sign Out (back to anonymous) ───────────────────────────────────────────
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
        // Re-enter anonymous mode.
        Task { await signInAnonymouslyIfNeeded() }
    }
}
