// ShoppingFormView.swift
// HouseholdApp
//
// Sheet for adding a new shopping item or editing an existing one.
// Pass `item: nil` to create, or pass an existing ShoppingItem to edit.
//
// Fields: Name (required), Quantity, Item Type, Store, Assignee, Notes.
// Item types and stores are user-extensible — tap "+" to add new ones,
// long-press existing ones to delete them.

import SwiftUI
import CoreData

struct ShoppingFormView: View {

    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettings

    let item: ShoppingItem?

    // ── Form state ─────────────────────────────────────────────────────────────
    @State private var name       = ""
    @State private var quantity   = ""
    @State private var store      = ""
    @State private var itemType   = ""
    @State private var assignedTo = AssignedTo.both
    @State private var notes      = ""

    // ── "Add new" alert state ──────────────────────────────────────────────────
    @State private var showingNewStore    = false
    @State private var showingNewType     = false
    @State private var newStoreName       = ""
    @State private var newTypeName        = ""

    // ── Delete confirmation state ──────────────────────────────────────────────
    @State private var storeToDelete: String? = nil
    @State private var typeToDelete: String? = nil

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    init(item: ShoppingItem?) {
        self.item = item
    }

    var body: some View {
        NavigationStack {
            Form {

                // ── Name + Quantity ────────────────────────────────────────────
                Section {
                    TextField("Item name", text: $name)
                    TextField("Quantity (optional)", text: $quantity)
                        .textInputAutocapitalization(.never)
                }

                // ── Who ────────────────────────────────────────────────────────
                Section("Who's buying") {
                    Picker("Assign to", selection: $assignedTo) {
                        ForEach(AssignedTo.allCases) { person in
                            Label(
                                person == .me      ? appSettings.myName :
                                person == .partner ? appSettings.partnerName :
                                "Both",
                                systemImage: appSettings.icon(for: person)
                            )
                            .tag(person)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // ── Item Type (pill selector) ─────────────────────────────────
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // "None" pill
                            pillButton(label: "None", icon: "xmark.circle", isSelected: itemType.isEmpty, color: .secondary) {
                                itemType = ""
                            }
                            ForEach(appSettings.itemTypes, id: \.self) { type in
                                pillButton(label: type, icon: "tag.fill", isSelected: itemType == type, color: .orange) {
                                    itemType = type
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        typeToDelete = type
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                            // Add pill
                            addPill {
                                newTypeName = ""
                                showingNewType = true
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Type")
                } footer: {
                    Text("Long press a type to delete it.")
                }

                // ── Store (pill selector) ─────────────────────────────────────
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // "None" pill
                            pillButton(label: "None", icon: "xmark.circle", isSelected: store.isEmpty, color: .secondary) {
                                store = ""
                            }
                            ForEach(appSettings.stores, id: \.self) { s in
                                pillButton(label: s, icon: "storefront.fill", isSelected: store == s, color: .green) {
                                    store = s
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        storeToDelete = s
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                            // Add pill
                            addPill {
                                newStoreName = ""
                                showingNewStore = true
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Store")
                } footer: {
                    Text("Long press a store to delete it.")
                }

                // ── Notes ──────────────────────────────────────────────────────
                Section("Notes (optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }
            }
            .navigationTitle(item == nil ? "New Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: populateIfEditing)

            // ── Add new store alert ────────────────────────────────────────────
            .alert("New Store", isPresented: $showingNewStore) {
                TextField("Store name", text: $newStoreName)
                Button("Add") {
                    let trimmed = newStoreName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        appSettings.addStore(trimmed)
                        store = trimmed
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter the name of the store.")
            }

            // ── Add new type alert ─────────────────────────────────────────────
            .alert("New Type", isPresented: $showingNewType) {
                TextField("Type name", text: $newTypeName)
                Button("Add") {
                    let trimmed = newTypeName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        appSettings.addItemType(trimmed)
                        itemType = trimmed
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter the name of the item type.")
            }

            // ── Delete store confirmation ──────────────────────────────────────
            .alert(
                "Delete Store?",
                isPresented: Binding(
                    get: { storeToDelete != nil },
                    set: { if !$0 { storeToDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let name = storeToDelete {
                        if store == name { store = "" }
                        appSettings.removeStore(name)
                    }
                    storeToDelete = nil
                }
                Button("Cancel", role: .cancel) { storeToDelete = nil }
            } message: {
                Text("Remove \"\(storeToDelete ?? "")\" from the store list?")
            }

            // ── Delete type confirmation ───────────────────────────────────────
            .alert(
                "Delete Type?",
                isPresented: Binding(
                    get: { typeToDelete != nil },
                    set: { if !$0 { typeToDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let name = typeToDelete {
                        if itemType == name { itemType = "" }
                        appSettings.removeItemType(name)
                    }
                    typeToDelete = nil
                }
                Button("Cancel", role: .cancel) { typeToDelete = nil }
            } message: {
                Text("Remove \"\(typeToDelete ?? "")\" from the type list?")
            }
        }
    }

    // ── Pill button helper ─────────────────────────────────────────────────────

    private func pillButton(label: String, icon: String, isSelected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? .white : color)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    isSelected ? color : color.opacity(0.12),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    /// "+" pill at the end of a row to add a new item.
    private func addPill(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Add", systemImage: "plus")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Color.accentColor.opacity(0.12),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    // ── Actions ────────────────────────────────────────────────────────────────

    private func populateIfEditing() {
        guard let item else { return }
        name       = item.nameSafe
        quantity   = item.quantity ?? ""
        store      = item.store ?? ""
        itemType   = item.itemType ?? ""
        assignedTo = item.assignedToEnum
        notes      = item.notes ?? ""
    }

    private func save() {
        let target = item ?? ShoppingItem(context: ctx)

        target.id             = target.id ?? UUID()
        target.name           = name.trimmingCharacters(in: .whitespaces)
        target.quantity       = quantity.isEmpty ? nil : quantity
        target.store          = store.isEmpty ? nil : store
        target.itemType       = itemType.isEmpty ? nil : itemType
        target.assignedToEnum = assignedTo
        target.notes          = notes.isEmpty ? nil : notes
        target.createdAt      = target.createdAt ?? Date()

        try? ctx.save()
        dismiss()
    }
}

#Preview {
    ShoppingFormView(item: nil)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(AppSettings())
}
