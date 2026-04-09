// AppSettings.swift
// HouseholdApp
//
// Lightweight observable wrapper around UserDefaults (@AppStorage) for
// user-configurable settings that don't belong in Core Data.
//
// Inject via .environmentObject(AppSettings()) in HouseholdAppApp,
// then read with @EnvironmentObject var appSettings: AppSettings.

import SwiftUI
import Combine

class AppSettings: ObservableObject {

    // ── Person names ──────────────────────────────────────────────────────────
    // These default to "Me" and "Partner" but the user can change them in
    // SettingsView. @AppStorage persists automatically to UserDefaults.

    @AppStorage("myName")
    var myName: String = "Me" {
        willSet { objectWillChange.send() }
    }

    @AppStorage("partnerName")
    var partnerName: String = "Partner" {
        willSet { objectWillChange.send() }
    }

    // ── Shopping: user-addable stores ──────────────────────────────────────────
    // Stored as a comma-separated string in UserDefaults. Merged with defaults.

    static let defaultStores = ["Costco", "Zehrs", "Home Depot", "Walmart", "Amazon"]

    @AppStorage("customStores")
    private var customStoresRaw: String = "" {
        willSet { objectWillChange.send() }
    }

    @AppStorage("hiddenStores")
    private var hiddenStoresRaw: String = "" {
        willSet { objectWillChange.send() }
    }

    /// All available store names (defaults + user-added, minus hidden), sorted alphabetically.
    var stores: [String] {
        let custom = customStoresRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let hidden = Set(hiddenStoresRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) })
        return Array(Set(Self.defaultStores + custom)).filter { !hidden.contains($0) }.sorted()
    }

    /// Adds a new store name. Ignored if it already exists.
    func addStore(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !stores.contains(trimmed) else { return }
        customStoresRaw += customStoresRaw.isEmpty ? trimmed : ",\(trimmed)"
    }

    /// Removes a store. If it's a default, adds it to the hidden list. If custom, removes it.
    func removeStore(_ name: String) {
        // Remove from custom stores if present
        let custom = customStoresRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0 != name && !$0.isEmpty }
        customStoresRaw = custom.joined(separator: ",")
        // If it's a default store, add to hidden list
        if Self.defaultStores.contains(name) {
            hiddenStoresRaw += hiddenStoresRaw.isEmpty ? name : ",\(name)"
        }
    }

    // ── Shopping: user-addable item types ──────────────────────────────────────

    static let defaultItemTypes = ["Food", "Furniture", "Maintenance", "Household", "Personal Care"]

    @AppStorage("customItemTypes")
    private var customItemTypesRaw: String = "" {
        willSet { objectWillChange.send() }
    }

    @AppStorage("hiddenItemTypes")
    private var hiddenItemTypesRaw: String = "" {
        willSet { objectWillChange.send() }
    }

    /// All available item type names (defaults + user-added, minus hidden), sorted alphabetically.
    var itemTypes: [String] {
        let custom = customItemTypesRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let hidden = Set(hiddenItemTypesRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) })
        return Array(Set(Self.defaultItemTypes + custom)).filter { !hidden.contains($0) }.sorted()
    }

    /// Adds a new item type name. Ignored if it already exists.
    func addItemType(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !itemTypes.contains(trimmed) else { return }
        customItemTypesRaw += customItemTypesRaw.isEmpty ? trimmed : ",\(trimmed)"
    }

    /// Removes an item type. If it's a default, adds it to the hidden list. If custom, removes it.
    func removeItemType(_ name: String) {
        let custom = customItemTypesRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0 != name && !$0.isEmpty }
        customItemTypesRaw = custom.joined(separator: ",")
        if Self.defaultItemTypes.contains(name) {
            hiddenItemTypesRaw += hiddenItemTypesRaw.isEmpty ? name : ",\(name)"
        }
    }

    // ── Convenience helpers ────────────────────────────────────────────────────

    /// Returns the display name for a given assignee value.
    func name(for assignee: AssignedTo) -> String {
        switch assignee {
        case .me:      return myName
        case .partner: return partnerName
        case .both:    return "\(myName) & \(partnerName)"
        }
    }

    /// SF Symbol name used to represent each assignee in the UI.
    func icon(for assignee: AssignedTo) -> String {
        switch assignee {
        case .me:      return "person.fill"
        case .partner: return "person.fill"
        case .both:    return "person.2.fill"
        }
    }
}
