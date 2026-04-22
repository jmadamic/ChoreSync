// ShoppingFormView.swift
import SwiftUI

private struct IdentifiableString: Identifiable {
    let id: String; var value: String { id }
    init(value: String) { self.id = value }
}

struct ShoppingFormView: View {

    @Environment(\.dismiss)           private var dismiss
    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var shoppingStore: ShoppingStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    let item: ShoppingItemDoc?

    @State private var name            = ""
    @State private var quantity        = ""
    @State private var store           = ""
    @State private var itemType        = ""
    @State private var selectedMembers: Set<Int> = []
    @State private var notes           = ""

    @State private var showingAddStore = false
    @State private var storeToEdit: String? = nil
    @State private var showingAddType  = false
    @State private var typeToEdit: String? = nil

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var householdId: String { householdCtrl.household?.id ?? "" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item name", text: $name)
                    TextField("Quantity (optional)", text: $quantity).textInputAutocapitalization(.never)
                }

                Section("Who's buying") {
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

                Section("Type") {
                    Picker("Item type", selection: $itemType) {
                        Text("None").tag("")
                        ForEach(appSettings.itemTypes, id: \.self) { t in
                            AppIconLabel(title: t, icon: appSettings.iconForItemType(t)).tag(t)
                        }
                    }
                    Button { showingAddType = true } label: {
                        Label("Add New Type...", systemImage: "plus.circle").font(.subheadline)
                    }
                    if !itemType.isEmpty {
                        Button { typeToEdit = itemType } label: {
                            Label("Edit \"\(itemType)\"", systemImage: "pencil").font(.subheadline)
                        }
                    }
                }

                Section("Store") {
                    Picker("Store", selection: $store) {
                        Text("None").tag("")
                        ForEach(appSettings.stores, id: \.self) { s in
                            AppIconLabel(title: s, icon: appSettings.iconForStore(s)).tag(s)
                        }
                    }
                    Button { showingAddStore = true } label: {
                        Label("Add New Store...", systemImage: "plus.circle").font(.subheadline)
                    }
                    if !store.isEmpty {
                        Button { storeToEdit = store } label: {
                            Label("Edit \"\(store)\"", systemImage: "pencil").font(.subheadline)
                        }
                    }
                }

                Section("Notes (optional)") {
                    TextEditor(text: $notes).frame(minHeight: 60)
                }
            }
            .navigationTitle(item == nil ? "New Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid).fontWeight(.semibold)
                }
            }
            .onAppear(perform: populate)
            .sheet(isPresented: $showingAddStore) {
                StoreFormView(originalName: nil) { store = $0 }
            }
            .sheet(item: Binding(
                get: { storeToEdit.map { IdentifiableString(value: $0) } },
                set: { storeToEdit = $0?.value }
            )) { w in StoreFormView(originalName: w.value, onDelete: { store = "" }, onSave: { store = $0 }) }
            .sheet(isPresented: $showingAddType) {
                ItemTypeFormView(originalName: nil) { itemType = $0 }
            }
            .sheet(item: Binding(
                get: { typeToEdit.map { IdentifiableString(value: $0) } },
                set: { typeToEdit = $0?.value }
            )) { w in ItemTypeFormView(originalName: w.value, onDelete: { itemType = "" }, onSave: { itemType = $0 }) }
        }
    }

    private func isMemberIncluded(_ idx: Int) -> Bool { selectedMembers.isEmpty || selectedMembers.contains(idx) }

    private func toggleMember(_ idx: Int) {
        if selectedMembers.isEmpty {
            guard appSettings.members.count > 1 else { return }
            selectedMembers = Set(appSettings.members.indices.filter { $0 != idx })
        } else if selectedMembers.contains(idx) {
            var u = selectedMembers; u.remove(idx); if !u.isEmpty { selectedMembers = u }
        } else {
            var u = selectedMembers; u.insert(idx)
            selectedMembers = u.count == appSettings.members.count ? [] : u
        }
    }

    private func populate() {
        guard let i = item else { return }
        name = i.name; quantity = i.quantity ?? ""; store = i.store ?? ""
        itemType = i.itemType ?? ""; selectedMembers = Set(i.assignedToMembers); notes = i.notes ?? ""
    }

    private func save() {
        var target = item ?? ShoppingItemDoc(
            id: UUID().uuidString, name: "", quantity: nil, store: nil, itemType: nil,
            assignedToMembers: [], isPurchased: false, purchasedAt: nil, notes: nil,
            sortOrder: 0, createdAt: Date()
        )
        target.name             = name.trimmingCharacters(in: .whitespaces)
        target.quantity         = quantity.isEmpty ? nil : quantity
        target.store            = store.isEmpty ? nil : store
        target.itemType         = itemType.isEmpty ? nil : itemType
        target.assignedToMembers = selectedMembers.sorted()
        target.notes            = notes.isEmpty ? nil : notes
        shoppingStore.save(target, householdId: householdId)
        dismiss()
    }
}
