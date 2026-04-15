// AuthController.swift
// HouseholdApp
//
// Wraps Firebase Auth + Google Sign-In. Publishes the current user so views
// can gate on sign-in state.
//
// Usage:
//   @StateObject var auth = AuthController()
//   auth.signInWithGoogle(presenting: uiViewController)
//   auth.signOut()

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
        // Kick off listening to Firebase Auth state changes.
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.user = user }
        }
    }

    deinit {
        if let handle = authListener {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    var isSignedIn: Bool { user != nil }
    var uid: String? { user?.uid }
    var displayName: String? { user?.displayName }
    var email: String? { user?.email }

    // ── Google Sign-In ─────────────────────────────────────────────────────────
    func signInWithGoogle(presenting: UIViewController) async {
        errorMessage = nil
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Firebase is not configured (missing GoogleService-Info.plist?)"
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
            _ = try await Auth.auth().signIn(with: credential)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // ── Sign Out ───────────────────────────────────────────────────────────────
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
    }
}
