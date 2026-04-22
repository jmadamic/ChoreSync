// ChoreListView.swift
import SwiftUI

struct ChoreListView: View {

    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var choreStore:    ChoreStore
    @EnvironmentObject private var categoryStore: CategoryStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    @State private var filterIndex     = -2   // -2=All, 0+=member
    @State private var showingAddChore = false
    @State private var choreToEdit: ChoreDoc?  = nil
    @State private var showDeleteAlert = false
    @State private var choreToDelete: ChoreDoc? = nil

    private var householdId: String { householdCtrl.household?.id ?? "" }

    private var filteredChores: [ChoreDoc] {
        guard filterIndex >= 0 else { return choreStore.chores }
        return choreStore.chores.filter {
            $0.assignedToMembers.isEmpty || $0.assignedToMembers.contains(filterIndex)
        }
    }

    private var sections: [ChoreSection] {
        let order: [ChoreSection] = [.overdue, .today, .thisWeek, .thisMonth, .upcoming, .noDate, .completed]
        let present = Set(filteredChores.map { $0.section })
        return order.filter { present.contains($0) }
    }

    private func chores(in section: ChoreSection) -> [ChoreDoc] {
        filteredChores.filter { $0.section == section }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                if filteredChores.isEmpty {
                    ContentUnavailableView("No Chores", systemImage: "checkmark.seal.fill",
                                          description: Text("Tap + to add your first chore."))
                } else {
                    List {
                        ForEach(sections, id: \.self) { section in
                            Section {
                                ForEach(chores(in: section)) { chore in
                                    ChoreRowView(chore: chore)
                                        .contentShape(Rectangle())
                                        .onTapGesture { choreToEdit = chore }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                choreToDelete = chore; showDeleteAlert = true
                                            } label: { Label("Delete", systemImage: "trash") }
                                        }
                                        .swipeActions(edge: .leading) {
                                            completeSwipeAction(for: chore)
                                        }
                                }
                            } header: { sectionHeader(section) }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Chores")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAddChore = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingAddChore)   { ChoreFormView(chore: nil) }
            .sheet(item: $choreToEdit)              { ChoreFormView(chore: $0) }
            .alert("Delete Chore?", isPresented: $showDeleteAlert, presenting: choreToDelete) { chore in
                Button("Delete", role: .destructive) {
                    choreStore.delete(chore, householdId: householdId)
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("\"\($0.titleSafe)\" will be permanently deleted.") }
        }
    }

    private var filterBar: some View {
        Picker("Filter", selection: $filterIndex) {
            Text("All").tag(-2)
            ForEach(Array(appSettings.members.indices), id: \.self) { idx in
                Text(appSettings.memberName(at: idx)).tag(idx)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal).padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }

    private func sectionHeader(_ section: ChoreSection) -> some View {
        HStack {
            Text(section.rawValue)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(section == .overdue ? .red : .secondary)
            Spacer()
            Text("\(chores(in: section).count)").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func completeSwipeAction(for chore: ChoreDoc) -> some View {
        if chore.isCompleted {
            Button {
                choreStore.markIncomplete(chore, householdId: householdId)
            } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
            .tint(.orange)
        } else {
            Button {
                choreStore.markComplete(chore, byMemberIndex: 0, householdId: householdId)
            } label: { Label("Done", systemImage: "checkmark") }
            .tint(.green)
        }
    }
}
