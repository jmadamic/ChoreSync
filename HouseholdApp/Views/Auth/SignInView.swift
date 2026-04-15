// SignInView.swift
// HouseholdApp
//
// Shown when the user is not yet signed in. Single "Sign in with Google" button.

import SwiftUI

struct SignInView: View {
    @EnvironmentObject var auth: AuthController

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "house.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor)

            Text("HouseholdApp")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Shared chores and shopping for two people.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button {
                Task { await signIn() }
            } label: {
                HStack {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                    Text("Sign in with Google")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)

            if let error = auth.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
    }

    @MainActor
    private func signIn() async {
        guard let root = Self.topViewController() else { return }
        await auth.signInWithGoogle(presenting: root)
    }

    /// Walk the UIWindow scene to find the top-most view controller for presenting.
    static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return nil }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

#Preview {
    SignInView()
        .environmentObject(AuthController())
}
