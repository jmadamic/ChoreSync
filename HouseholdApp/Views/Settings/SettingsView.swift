// SettingsView.swift
// HouseholdApp
//
// Lets each person configure their display name, manage household sharing,
// and view app info.
//
// The "Household Sharing" section is the key addition for CloudKit sharing:
//   - If not sharing yet: shows "Invite Partner" button
//   - If sharing: shows participants and a "Manage" button

import SwiftUI
import CoreData
import CloudKit

struct SettingsView: View {

    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var shareController: ShareController
    @Environment(\.managedObjectContext) private var ctx

    let persistence = PersistenceController.shared

    // Track counts for the "Data" section.
    @FetchRequest(sortDescriptors: []) private var allChores:         FetchedResults<Chore>
    @FetchRequest(sortDescriptors: []) private var allShoppingItems:  FetchedResults<ShoppingItem>

    // Confirmation for "Delete All Data" action.
    @State private var showingDeleteAlert = false

    var body: some View {
        NavigationStack {
            Form {

                // ── People ─────────────────────────────────────────────────────
                Section {
                    personRow(
                        label:       "Your name",
                        placeholder: "e.g. Alex",
                        binding:     $appSettings.myName,
                        color:       AssignedTo.me.color
                    )
                    personRow(
                        label:       "Partner's name",
                        placeholder: "e.g. Jordan",
                        binding:     $appSettings.partnerName,
                        color:       AssignedTo.partner.color
                    )
                } header: {
                    Text("People")
                } footer: {
                    Text("Names appear in the chore list and assignment picker.")
                }

                // ── Household Sharing ──────────────────────────────────────────
                Section {
                    if shareController.isSharing {
                        // Currently sharing — show participants.
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Household Linked")
                                    .font(.body)
                                Text("\(shareController.participantNames.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }

                        // Manage button — opens the UICloudSharingController
                        // to add/remove participants or copy the share link.
                        Button {
                            shareController.manageShare()
                        } label: {
                            Label("Manage Sharing", systemImage: "person.crop.circle.badge.checkmark")
                        }

                        // Stop sharing.
                        Button(role: .destructive) {
                            Task { await shareController.stopSharing() }
                        } label: {
                            Label("Stop Sharing", systemImage: "person.crop.circle.badge.xmark")
                        }

                    } else {
                        // Not sharing yet — show invite button.
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Not linked yet")
                                    .font(.body)
                                Text("Invite your partner to share chores")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "person.2.slash")
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            Task { await shareController.createShare() }
                        } label: {
                            Label("Invite Partner", systemImage: "person.badge.plus")
                                .fontWeight(.semibold)
                        }
                    }
                } header: {
                    Text("Household Sharing")
                } footer: {
                    if shareController.isSharing {
                        Text("Both of you can add, edit, and complete chores. Each person uses their own Apple ID.")
                    } else {
                        Text("Tap \"Invite Partner\" to send an iCloud sharing link. Your partner opens it to join your household. Each of you keeps your own Apple ID — no shared account needed.")
                    }
                }

                // ── Error display ──────────────────────────────────────────────
                if let error = shareController.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                // ── Data summary ───────────────────────────────────────────────
                Section("Data") {
                    LabeledContent("Chores",         value: "\(allChores.count)")
                    LabeledContent("Shopping Items",  value: "\(allShoppingItems.count)")
                    LabeledContent("Completed",      value: "\(allChores.filter(\.isCompleted).count)")
                }

                // ── Danger zone ────────────────────────────────────────────────
                Section {
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label("Delete All Data", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("This permanently deletes all chores, shopping items, categories, and completion history.")
                }

                // ── About ──────────────────────────────────────────────────────
                Section("About") {
                    LabeledContent("Version") {
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Built with") {
                        Text("SwiftUI + CloudKit")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Delete All Data?", isPresented: $showingDeleteAlert) {
                Button("Delete Everything", role: .destructive, action: deleteAllData)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all chores, shopping items, categories, and completion history. This cannot be undone.")
            }
            // ── CloudKit sharing sheet ──────────────────────────────────────
            .sheet(isPresented: $shareController.showingSharingSheet) {
                if let share = shareController.activeShare {
                    CloudSharingSheet(
                        share: share,
                        container: persistence.container
                    ) {
                        // On dismiss: refresh status.
                        shareController.showingSharingSheet = false
                        Task { await shareController.refreshShareStatus() }
                    }
                }
            }
        }
    }

    // ── Subviews ───────────────────────────────────────────────────────────────

    /// A row with a colour-dot avatar and an inline text field for name entry.
    private func personRow(label: String, placeholder: String, binding: Binding<String>, color: Color) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(placeholder, text: binding)
                    .font(.body)
            }
        }
        .padding(.vertical, 2)
    }

    // ── Actions ────────────────────────────────────────────────────────────────

    /// Deletes all chores, shopping items, categories, and completion logs.
    private func deleteAllData() {
        // Delete all chores (cascade deletes their CompletionLogs).
        let choreRequest: NSFetchRequest<NSFetchRequestResult> = Chore.fetchRequest()
        let choreBatch = NSBatchDeleteRequest(fetchRequest: choreRequest)
        choreBatch.resultType = .resultTypeObjectIDs

        // Delete all shopping items.
        let shoppingRequest: NSFetchRequest<NSFetchRequestResult> = ShoppingItem.fetchRequest()
        let shoppingBatch = NSBatchDeleteRequest(fetchRequest: shoppingRequest)
        shoppingBatch.resultType = .resultTypeObjectIDs

        // Delete all categories.
        let categoryRequest: NSFetchRequest<NSFetchRequestResult> = Category.fetchRequest()
        let categoryBatch = NSBatchDeleteRequest(fetchRequest: categoryRequest)
        categoryBatch.resultType = .resultTypeObjectIDs

        // Delete all completion logs (in case any orphans remain).
        let logRequest: NSFetchRequest<NSFetchRequestResult> = CompletionLog.fetchRequest()
        let logBatch = NSBatchDeleteRequest(fetchRequest: logRequest)
        logBatch.resultType = .resultTypeObjectIDs

        do {
            let results = try [choreBatch, shoppingBatch, categoryBatch, logBatch].map {
                try ctx.execute($0) as? NSBatchDeleteResult
            }
            // Merge changes into the view context so the UI updates.
            let objectIDs = results.compactMap { $0?.result as? [NSManagedObjectID] }.flatMap { $0 }
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                into: [ctx]
            )
        } catch {
            print("Failed to delete all data: \(error.localizedDescription)")
        }
    }
}

#Preview {
    SettingsView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AppSettings())
        .environmentObject(ShareController(persistence: .preview))
}
