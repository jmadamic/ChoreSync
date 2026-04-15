// HouseholdSetupView.swift
// HouseholdApp
//
// Shown after sign-in when the user hasn't joined a household yet.
// Two paths: create a new household, or join via invite code.

import SwiftUI

struct HouseholdSetupView: View {
    @EnvironmentObject var auth: AuthController
    @EnvironmentObject var household: HouseholdController

    @State private var newHouseholdName = ""
    @State private var inviteCode = ""

    var body: some View {
        NavigationStack {
            Form {

                // ── Create new ─────────────────────────────────────────────────
                Section("Create a Household") {
                    TextField("Household name (optional)", text: $newHouseholdName)
                    Button {
                        Task {
                            await household.createHousehold(
                                name: newHouseholdName.trimmingCharacters(in: .whitespaces)
                            )
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Create Household", systemImage: "house.fill")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(household.isBusy)
                } footer: {
                    Text("Creates a new household with you as the owner. You'll get an invite code to share.")
                }

                // ── Join existing ──────────────────────────────────────────────
                Section("Join a Household") {
                    TextField("Invite code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.title3, design: .monospaced))
                    Button {
                        Task { await household.joinHousehold(code: inviteCode) }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Join Household", systemImage: "person.badge.plus")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(household.isBusy || inviteCode.isEmpty)
                } footer: {
                    Text("Ask the person who created the household for the 6-character invite code.")
                }

                // ── Error ──────────────────────────────────────────────────────
                if let error = household.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                // ── Sign out ───────────────────────────────────────────────────
                Section {
                    Button(role: .destructive) {
                        auth.signOut()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                            Spacer()
                        }
                    }
                } footer: {
                    if let email = auth.email {
                        Text("Signed in as \(email)")
                    }
                }
            }
            .navigationTitle("Welcome")
            .overlay {
                if household.isBusy {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
        }
    }
}

#Preview {
    HouseholdSetupView()
        .environmentObject(AuthController())
        .environmentObject(HouseholdController())
}
