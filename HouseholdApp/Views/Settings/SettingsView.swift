// SettingsView.swift
// HouseholdApp

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var auth:          AuthController
    @EnvironmentObject private var householdCtrl: HouseholdController
    @EnvironmentObject private var choreStore:    ChoreStore
    @EnvironmentObject private var shoppingStore: ShoppingStore

    @State private var showingDeleteAlert = false
    @State private var showingAddMember   = false
    @State private var newMemberName      = ""
    @State private var showingLeaveAlert  = false
    @State private var copiedCode         = false
    @State private var showingJoinSheet   = false
    @State private var joinCode           = ""

    var body: some View {
        NavigationStack {
            Form {

                // ── Household Members ─────────────────────────────────────────
                Section {
                    ForEach(Array(appSettings.members.enumerated()), id: \.offset) { index, name in
                        memberRow(index: index, name: name)
                    }
                    Button { newMemberName = ""; showingAddMember = true } label: {
                        Label("Add Member", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text("Household Members")
                } footer: {
                    Text("Names appear in assignment pickers. Each device sets names locally.")
                }

                // ── Household Sharing ──────────────────────────────────────────
                if let household = householdCtrl.household {
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Invite Code")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Text(household.inviteCode)
                                    .font(.system(.title2, design: .monospaced).weight(.bold))
                                    .foregroundStyle(.blue)
                            }
                            Spacer()
                            Button {
                                UIPasteboard.general.string = household.inviteCode
                                copiedCode = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedCode = false }
                            } label: {
                                Image(systemName: copiedCode ? "checkmark" : "doc.on.doc")
                                    .foregroundStyle(copiedCode ? .green : .blue)
                            }
                        }
                        .padding(.vertical, 4)

                        Text("\(household.memberIds.count) member(s) in this household")
                            .font(.caption).foregroundStyle(.secondary)

                        Button { showingJoinSheet = true } label: {
                            Label("Join a Different Household", systemImage: "person.badge.plus")
                        }
                        Button(role: .destructive) { showingLeaveAlert = true } label: {
                            Label("Leave Household", systemImage: "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(.red)
                        }
                    } header: {
                        Text("Household Sharing")
                    } footer: {
                        Text("Share your invite code with others so they can join. Or join someone else's household with their code.")
                    }
                }

                // ── Account ────────────────────────────────────────────────────
                Section("Account") {
                    if auth.isAnonymous {
                        Button {
                            Task {
                                guard let root = SignInView.topViewController() else { return }
                                await auth.signInWithGoogle(presenting: root)
                            }
                        } label: {
                            Label("Sign in with Google to sync", systemImage: "person.crop.circle.badge.checkmark")
                        }
                    } else {
                        if let email = auth.email {
                            LabeledContent("Signed in as", value: email)
                        }
                        Button(role: .destructive) { auth.signOut() } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }

                // ── Data summary ───────────────────────────────────────────────
                Section("Data") {
                    LabeledContent("Chores",         value: "\(choreStore.chores.count)")
                    LabeledContent("Shopping Items",  value: "\(shoppingStore.items.count)")
                    LabeledContent("Completed",      value: "\(choreStore.chores.filter(\.isCompleted).count)")
                }

                // ── Danger zone ────────────────────────────────────────────────
                Section {
                    Button(role: .destructive) { showingDeleteAlert = true } label: {
                        Label("Delete All Data", systemImage: "trash").foregroundStyle(.red)
                    }
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("Permanently deletes all chores, shopping items, categories, and completion history.")
                }

                // ── Appearance ─────────────────────────────────────────────────
                Section("Appearance") {
                    Picker(selection: $appSettings.appearance) {
                        ForEach(AppAppearance.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                        }
                    } label: {
                        Label("Theme", systemImage: appSettings.appearance.icon)
                    }
                    .pickerStyle(.menu)
                }

                // ── About ──────────────────────────────────────────────────────
                Section("About") {
                    LabeledContent("Version") {
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Delete All Data?", isPresented: $showingDeleteAlert) {
                Button("Delete Everything", role: .destructive, action: deleteAll)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes all chores and shopping items. Cannot be undone.")
            }
            .alert("Leave Household?", isPresented: $showingLeaveAlert) {
                Button("Leave", role: .destructive) {
                    Task { await householdCtrl.leaveHousehold() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll lose access to shared chores and shopping items.")
            }
            .alert("Add Member", isPresented: $showingAddMember) {
                TextField("Name", text: $newMemberName)
                Button("Add") {
                    let t = newMemberName.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { appSettings.addMember(t) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter the name for the new household member.")
            }
            .alert("Join a Household", isPresented: $showingJoinSheet) {
                TextField("6-character invite code", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Join") {
                    Task { await householdCtrl.joinHousehold(code: joinCode) }
                }
                Button("Cancel", role: .cancel) { joinCode = "" }
            } message: {
                Text("Enter the invite code from the other person's Settings screen.")
            }
        }
    }

    // ── Subviews ───────────────────────────────────────────────────────────────

    @ViewBuilder
    private func memberRow(index: Int, name: String) -> some View {
        HStack(spacing: 12) {
            Circle().fill(appSettings.memberColor(at: index)).frame(width: 28, height: 28)
                .overlay(Image(systemName: "person.fill").font(.caption).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text("Member \(index + 1)").font(.subheadline).foregroundStyle(.secondary)
                TextField("Name", text: memberBinding(at: index)).font(.body)
            }
            Spacer()
            if appSettings.members.count > 1 && index >= 2 {
                Button(role: .destructive) { appSettings.removeMember(at: index) } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    private func memberBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { appSettings.memberName(at: index) },
            set: { appSettings.renameMember(at: index, to: $0) }
        )
    }

    // ── Actions ────────────────────────────────────────────────────────────────

    private func deleteAll() {
        guard let hid = householdCtrl.household?.id else { return }
        choreStore.chores.forEach   { choreStore.delete($0,    householdId: hid) }
        shoppingStore.items.forEach { shoppingStore.delete($0, householdId: hid) }
    }
}
