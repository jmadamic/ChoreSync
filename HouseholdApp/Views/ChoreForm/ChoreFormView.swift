// ChoreFormView.swift
import SwiftUI

struct ChoreFormView: View {

    @Environment(\.dismiss)           private var dismiss
    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var choreStore:    ChoreStore
    @EnvironmentObject private var categoryStore: CategoryStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    let chore: ChoreDoc?

    @State private var title           = ""
    @State private var notes           = ""
    @State private var selectedMembers: Set<Int> = []
    @State private var dueDateType     = DueDateType.none
    @State private var dueDate         = Date()
    @State private var repeatInt       = RepeatInterval.none
    @State private var selectedCatId: String? = nil

    @State private var showingAddCategory = false
    @State private var categoryToEdit: CategoryDoc? = nil

    private var isValid: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }
    private var householdId: String { householdCtrl.household?.id ?? "" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Chore name", text: $title)
                }

                Section("Who") {
                    ForEach(Array(appSettings.members.indices), id: \.self) { idx in
                        Toggle(appSettings.memberName(at: idx), isOn: Binding(
                            get: { isMemberIncluded(idx) },
                            set: { _ in toggleMember(idx) }
                        ))
                        .tint(appSettings.memberColor(at: idx))
                    }
                    if !selectedMembers.isEmpty {
                        Button("Select All") { selectedMembers = [] }.foregroundStyle(.blue)
                    }
                }

                Section("Category") {
                    Picker("Category", selection: $selectedCatId) {
                        Text("None").tag(nil as String?)
                        ForEach(categoryStore.categories) { cat in
                            AppIconLabel(title: cat.nameSafe, icon: cat.iconNameSafe).tag(cat.id as String?)
                        }
                    }
                    Button { showingAddCategory = true } label: {
                        Label("Add New Category...", systemImage: "plus.circle").font(.subheadline)
                    }
                    if let cid = selectedCatId, let cat = categoryStore.categories.first(where: { $0.id == cid }) {
                        Button { categoryToEdit = cat } label: {
                            Label("Edit \"\(cat.nameSafe)\"", systemImage: "pencil").font(.subheadline)
                        }
                    }
                }

                Section("Due") {
                    Picker("Due date", selection: $dueDateType) {
                        ForEach(DueDateType.allCases) { type in
                            Label(type.label, systemImage: type.systemImage).tag(type)
                        }
                    }
                    if dueDateType == .specificDate {
                        DatePicker("Date", selection: $dueDate, displayedComponents: .date)
                    } else if dueDateType == .week {
                        DatePicker("Week of", selection: $dueDate, displayedComponents: .date)
                    } else if dueDateType == .month {
                        DatePicker("Month", selection: $dueDate, displayedComponents: .date)
                        Text(dueDate.formatted(.dateTime.month(.wide).year()))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Repeat") {
                    Picker("Repeats", selection: $repeatInt) {
                        ForEach(RepeatInterval.allCases) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                }

                Section("Notes (optional)") {
                    TextEditor(text: $notes).frame(minHeight: 80)
                }
            }
            .navigationTitle(chore == nil ? "New Chore" : "Edit Chore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid).fontWeight(.semibold)
                }
            }
            .onAppear(perform: populate)
            .sheet(isPresented: $showingAddCategory) {
                CategoryFormView(category: nil)
            }
            .sheet(item: $categoryToEdit) { cat in
                CategoryFormView(category: cat) { selectedCatId = nil }
            }
        }
    }

    private func isMemberIncluded(_ idx: Int) -> Bool {
        selectedMembers.isEmpty || selectedMembers.contains(idx)
    }

    private func toggleMember(_ idx: Int) {
        if selectedMembers.isEmpty {
            guard appSettings.members.count > 1 else { return }
            selectedMembers = Set(appSettings.members.indices.filter { $0 != idx })
        } else if selectedMembers.contains(idx) {
            var updated = selectedMembers; updated.remove(idx)
            if !updated.isEmpty { selectedMembers = updated }
        } else {
            var updated = selectedMembers; updated.insert(idx)
            selectedMembers = updated.count == appSettings.members.count ? [] : updated
        }
    }

    private func populate() {
        guard let c = chore else { return }
        title          = c.title
        notes          = c.notes ?? ""
        selectedMembers = Set(c.assignedToMembers)
        dueDateType    = c.dueDateTypeEnum
        dueDate        = c.dueDate ?? Date()
        repeatInt      = c.repeatIntervalEnum
        selectedCatId  = c.categoryId
    }

    private func save() {
        var target = chore ?? ChoreDoc(
            id: UUID().uuidString, title: "", notes: nil, assignedToMembers: [],
            dueDateType: 3, dueDate: nil, repeatInterval: 0,
            isCompleted: false, completedAt: nil, completedByMembers: [],
            categoryId: nil, sortOrder: 0, createdAt: Date()
        )
        target.title              = title.trimmingCharacters(in: .whitespaces)
        target.notes              = notes.isEmpty ? nil : notes
        target.assignedToMembers  = selectedMembers.sorted()
        target.dueDateTypeEnum    = dueDateType
        target.dueDate            = dueDateType == .none ? nil : dueDate
        target.repeatIntervalEnum = repeatInt
        target.categoryId         = selectedCatId
        choreStore.save(target, householdId: householdId)
        dismiss()
    }
}
