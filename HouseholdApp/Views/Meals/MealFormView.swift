// MealFormView.swift
import SwiftUI

struct MealFormView: View {

    @Environment(\.dismiss)           private var dismiss
    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var mealStore:     MealStore
    @EnvironmentObject private var shoppingStore: ShoppingStore
    @EnvironmentObject private var tripStore:     TripStore
    @EnvironmentObject private var packingStore:  PackingStore
    @EnvironmentObject private var savedMealStore: SavedMealStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    let meal: MealDoc?
    /// When set (and `meal` is nil), the form prefills from this saved meal.
    var template: SavedMealDoc? = nil

    // Stable ID up front so grocery items created mid-edit link correctly.
    @State private var mealId          = UUID().uuidString
    @State private var name            = ""
    @State private var day             = Calendar.current.startOfDay(for: .now)
    @State private var mealType: MealType = .dinner
    @State private var selectedMembers: Set<Int> = []
    @State private var ingredients: [MealIngredient] = []
    @State private var newIngredient   = ""
    @State private var notes           = ""
    @State private var tripId: String? = nil
    @State private var recipeURL       = ""
    @State private var instructions    = ""
    @State private var savedToLibrary  = false

    private var householdId: String { householdCtrl.household?.id ?? "" }

    /// Ingredients marked "need to buy" that aren't on the shopping list yet —
    /// these become shopping items when the meal is saved.
    private var pendingToBuy: [MealIngredient] {
        ingredients.filter { !$0.have && !$0.addedToList }
    }

    /// Title used on linked grocery items.
    private var displayTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? mealType.label : trimmed
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Meal name (optional)", text: $name)
                } footer: {
                    Text("Leave blank to just show the meal type, e.g. \"Dinner\".")
                }

                Section("When") {
                    DatePicker("Day", selection: $day, displayedComponents: .date)
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases) { type in
                            Label(type.label, systemImage: type.icon).tag(type)
                        }
                    }
                }

                Section("Who's making it") {
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

                ingredientsSection

                if !tripStore.trips.isEmpty {
                    Section {
                        Picker("Trip / event", selection: $tripId) {
                            Text("None").tag(nil as String?)
                            ForEach(tripStore.trips) { trip in
                                Text("\(trip.nameSafe) (\(trip.dateRangeLabel))").tag(trip.id as String?)
                            }
                        }
                    } header: {
                        Text("Trip")
                    } footer: {
                        if tripId != nil {
                            Text("This meal's ingredients are added to the trip's packing list under Food.")
                        }
                    }
                }

                Section {
                    HStack {
                        TextField("Recipe link (optional)", text: $recipeURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if let url = validRecipeURL {
                            Link(destination: url) {
                                Image(systemName: "safari")
                            }
                            .accessibilityLabel("Open recipe link")
                        }
                    }
                    TextEditor(text: $instructions)
                        .frame(minHeight: 80)
                        .overlay(alignment: .topLeading) {
                            if instructions.isEmpty {
                                Text("Type out cooking instructions…")
                                    .foregroundStyle(Color(.placeholderText))
                                    .padding(.top, 8).padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("Recipe")
                } footer: {
                    Text("Paste a link to an online recipe and/or write the steps here. Both are included when you share the meal.")
                }

                Section("Notes (optional)") {
                    TextEditor(text: $notes).frame(minHeight: 60)
                }

                Section {
                    ShareLink(item: currentExportText()) {
                        Label("Share Meal", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        saveToLibrary()
                    } label: {
                        Label(savedToLibrary ? "Saved to My Meals" : "Save to My Meals",
                              systemImage: savedToLibrary ? "checkmark.circle.fill" : "text.book.closed")
                    }
                    .disabled(savedToLibrary || name.trimmingCharacters(in: .whitespaces).isEmpty)
                } footer: {
                    Text("Sharing sends the full meal (ingredients, recipe, instructions). Saving adds it to My Meals so you can plan it again anytime — a name is required.")
                }
            }
            .navigationTitle(meal == nil ? "New Meal" : "Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTapped() }.fontWeight(.semibold)
                }
            }
            .onAppear(perform: populate)
        }
    }

    // ── Ingredients ────────────────────────────────────────────────────────────

    private var ingredientsSection: some View {
        Section {
            ForEach($ingredients) { $ing in
                ingredientRow($ing)
            }
            .onDelete { ingredients.remove(atOffsets: $0) }

            HStack {
                Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                TextField("Add ingredient", text: $newIngredient)
                    .onSubmit(addIngredient)
                    .submitLabel(.done)
                if !newIngredient.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Add") { addIngredient() }
                        .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("Ingredients")
        } footer: {
            if ingredients.isEmpty {
                Text("Add what the meal needs, then tap the cart on anything you have to buy.")
            } else if pendingToBuy.isEmpty {
                Text("Tap the cart on an ingredient to add it to the shopping list when you save.")
            } else {
                Text("\(pendingToBuy.count) ingredient\(pendingToBuy.count == 1 ? "" : "s") will be added to the shopping list when you save, linked to this meal.")
            }
        }
    }

    private func ingredientRow(_ ing: Binding<MealIngredient>) -> some View {
        let needs = !ing.wrappedValue.have
        let onList = ing.wrappedValue.addedToList
        return HStack(spacing: 10) {
            TextField("Ingredient", text: ing.name)

            Spacer()

            if onList {
                // Already a shopping item from an earlier save — just show it.
                Label("On list", systemImage: "cart.fill")
                    .font(.caption).foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            } else {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    ing.wrappedValue.have.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: needs ? "cart.fill.badge.plus" : "cart.badge.plus")
                        if needs { Text("Buy").font(.caption.weight(.semibold)) }
                    }
                    .foregroundStyle(needs ? .orange : .secondary)
                    .frame(minWidth: 44, minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(needs
                    ? "\(ing.wrappedValue.name): will be added to the shopping list. Tap to mark as on hand."
                    : "\(ing.wrappedValue.name): on hand. Tap to add to the shopping list.")
            }
        }
    }

    private func addIngredient() {
        let trimmed = newIngredient.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        ingredients.append(MealIngredient(name: trimmed))
        newIngredient = ""
    }

    /// Builds shopping items for every ingredient marked "need to buy" that
    /// isn't on the list yet, and flags them so the meal remembers.
    /// Called at save time only — nothing is written while still editing,
    /// so cancelling the form never leaves orphaned shopping items.
    private func createShoppingItems(for ingredients: inout [MealIngredient]) {
        for idx in ingredients.indices where !ingredients[idx].have && !ingredients[idx].addedToList {
            let item = ShoppingItemDoc(
                id: UUID().uuidString,
                name: ingredients[idx].name.trimmingCharacters(in: .whitespaces),
                quantity: nil, store: nil, itemType: "Food",
                assignedToMembers: [], isPurchased: false, purchasedAt: nil,
                notes: nil, sortOrder: 0, createdAt: Date(),
                mealId: mealId, mealName: displayTitle
            )
            shoppingStore.save(item, householdId: householdId)
            ingredients[idx].addedToList = true
        }
    }

    // ── Members ────────────────────────────────────────────────────────────────

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

    // ── Populate / save ────────────────────────────────────────────────────────

    private func populate() {
        if let m = meal {
            mealId          = m.id
            name            = m.name ?? ""
            day             = m.day
            mealType        = m.mealTypeEnum
            selectedMembers = Set(m.assignedToMembers)
            ingredients     = m.ingredients
            notes           = m.notes ?? ""
            tripId          = m.tripId
            recipeURL       = m.recipeURL ?? ""
            instructions    = m.instructions ?? ""
        } else if let t = template {
            // Planning a saved meal: copy the dish, leave day/cook/trip fresh.
            name         = t.name
            mealType     = t.mealTypeEnum
            ingredients  = t.ingredientNames.map { MealIngredient(name: $0) }
            notes        = t.notes ?? ""
            recipeURL    = t.recipeURL ?? ""
            instructions = t.instructions ?? ""
        }
    }

    private var validRecipeURL: URL? {
        let trimmed = recipeURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let url = URL(string: trimmed),
              url.scheme == "http" || url.scheme == "https" else { return nil }
        return url
    }

    /// Export built from the CURRENT form fields (not the last-saved doc),
    /// so shares reflect what's on screen.
    private func currentExportText() -> String {
        var doc = MealDoc(
            id: mealId, name: nil, day: day, mealType: mealType.rawValue,
            assignedToMembers: selectedMembers.sorted(),
            ingredients: ingredients.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty },
            notes: notes.isEmpty ? nil : notes,
            isCompleted: false, completedAt: nil, createdAt: Date()
        )
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        doc.name         = trimmedName.isEmpty ? nil : trimmedName
        doc.recipeURL    = recipeURL.isEmpty ? nil : recipeURL
        doc.instructions = instructions.isEmpty ? nil : instructions
        return doc.exportText(memberNames: { appSettings.memberName(at: $0) })
    }

    private func saveToLibrary() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let saved = SavedMealDoc(
            id: UUID().uuidString,
            name: trimmedName,
            mealType: mealType.rawValue,
            ingredientNames: ingredients
                .map { $0.name.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            recipeURL: recipeURL.isEmpty ? nil : recipeURL,
            instructions: instructions.isEmpty ? nil : instructions,
            notes: notes.isEmpty ? nil : notes,
            createdAt: Date()
        )
        savedMealStore.save(saved, householdId: householdId)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        savedToLibrary = true
    }

    private func saveTapped() {
        // Capture any text sitting in the "add ingredient" field.
        addIngredient()
        save()
    }

    private func save() {
        var target = meal ?? MealDoc(
            id: mealId, name: nil, day: day, mealType: mealType.rawValue,
            assignedToMembers: [], ingredients: [], notes: nil,
            isCompleted: false, completedAt: nil, createdAt: Date()
        )
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        target.name              = trimmedName.isEmpty ? nil : trimmedName
        target.day               = Calendar.current.startOfDay(for: day)
        target.mealTypeEnum      = mealType
        target.assignedToMembers = selectedMembers.sorted()
        var kept = ingredients.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        createShoppingItems(for: &kept)
        target.ingredients       = kept
        target.notes             = notes.isEmpty ? nil : notes
        target.tripId            = tripId
        target.recipeURL         = recipeURL.isEmpty ? nil : recipeURL
        target.instructions      = instructions.isEmpty ? nil : instructions
        mealStore.save(target, householdId: householdId)
        if tripId != nil { syncIngredientsToPackingList(for: target) }
        dismiss()
    }

    /// When the meal is tied to a trip, every ingredient goes onto that trip's
    /// packing list under Food (skipping names already on the list).
    private func syncIngredientsToPackingList(for meal: MealDoc) {
        guard let tripId = meal.tripId else { return }
        for ing in meal.ingredients {
            let trimmed = ing.name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  !packingStore.hasItem(named: trimmed, tripId: tripId) else { continue }
            let item = PackingItemDoc(
                id: UUID().uuidString, tripId: tripId, name: trimmed,
                section: "Food", isPacked: false, packedAt: nil,
                createdAt: Date(), mealId: meal.id
            )
            packingStore.save(item, householdId: householdId)
        }
    }
}
