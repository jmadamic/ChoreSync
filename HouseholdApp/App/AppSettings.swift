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

// ── Notification preferences ─────────────────────────────────────────────────

enum NotifChoreFilter: String, CaseIterable, Identifiable {
    case all    = "all"
    case mine   = "mine"
    case shared = "shared"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:    return "All chores"
        case .mine:   return "My chores"
        case .shared: return "Shared (everyone)"
        }
    }
}

// ── Appearance ───────────────────────────────────────────────────────────────

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light  = "Light"
    case dark   = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }
}

class AppSettings: ObservableObject {

    // ── Notification preferences ─────────────────────────────────────────────
    // All stored in UserDefaults (device-local) so each phone configures independently.

    @AppStorage("notifDueDatesEnabled")
    var notifDueDatesEnabled: Bool = true {
        willSet { objectWillChange.send() }
    }

    @AppStorage("notifChoreFilter")
    private var notifChoreFilterRaw: String = NotifChoreFilter.all.rawValue {
        willSet { objectWillChange.send() }
    }
    var notifChoreFilter: NotifChoreFilter {
        get { NotifChoreFilter(rawValue: notifChoreFilterRaw) ?? .all }
        set { notifChoreFilterRaw = newValue.rawValue }
    }

    /// Which member index "I" am — used when notifChoreFilter == .mine.
    @AppStorage("myMemberIndex")
    var myMemberIndex: Int = 0 {
        willSet { objectWillChange.send() }
    }

    @AppStorage("notifDayOf")
    var notifDayOf: Bool = true {
        willSet { objectWillChange.send() }
    }

    @AppStorage("notifDayBefore")
    var notifDayBefore: Bool = true {
        willSet { objectWillChange.send() }
    }

    /// A hash of all notification preferences; observe this to reschedule when any pref changes.
    var notifSettingsHash: Int {
        var h = Hasher()
        h.combine(notifDueDatesEnabled)
        h.combine(notifChoreFilterRaw)
        h.combine(myMemberIndex)
        h.combine(notifDayOf)
        h.combine(notifDayBefore)
        return h.finalize()
    }

    // ── Appearance ───────────────────────────────────────────────────────────
    @AppStorage("appearanceMode")
    var appearanceRaw: String = AppAppearance.system.rawValue {
        willSet { objectWillChange.send() }
    }

    var appearance: AppAppearance {
        get { AppAppearance(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    // ── Household members ────────────────────────────────────────────────────
    // JSON-encoded array of member names, e.g. ["Jordan","Sarah","Alex"].
    // Member index 0 = first entry, index 1 = second, etc.

    @AppStorage("memberNames")
    private var memberNamesRaw: String = "" {
        willSet { objectWillChange.send() }
    }

    /// All current household member names, in order.
    var members: [String] {
        let decoded = decodeMemberNames()
        return decoded.isEmpty ? Self.defaultMembers : decoded
    }

    static let defaultMembers = ["Me", "Partner"]

    /// Convenience: first member name (backward compat).
    var myName: String {
        get { members.indices.contains(0) ? members[0] : "Me" }
        set { renameMember(at: 0, to: newValue) }
    }

    /// Convenience: second member name (backward compat).
    var partnerName: String {
        get { members.indices.contains(1) ? members[1] : "Partner" }
        set { renameMember(at: 1, to: newValue) }
    }

    /// Number of members in the household.
    var memberCount: Int { members.count }

    func addMember(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var list = members
        list.append(trimmed)
        encodeMemberNames(list)
    }

    func removeMember(at index: Int) {
        var list = members
        guard list.indices.contains(index), list.count > 1 else { return }
        list.remove(at: index)
        encodeMemberNames(list)
    }

    func renameMember(at index: Int, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var list = members
        // Expand list if needed (e.g. first launch, migrating from old format).
        while list.count <= index { list.append("Member \(list.count + 1)") }
        list[index] = trimmed
        encodeMemberNames(list)
    }

    func moveMember(from source: IndexSet, to destination: Int) {
        var list = members
        list.move(fromOffsets: source, toOffset: destination)
        encodeMemberNames(list)
    }

    // ── Member display helpers ────────────────────────────────────────────────

    func memberName(at index: Int) -> String {
        members.indices.contains(index) ? members[index] : "Member \(index + 1)"
    }

    func memberColor(at index: Int) -> Color {
        MemberAssignment.memberColors[index % MemberAssignment.memberColors.count]
    }

    /// Returns the display name for an assignee value (stored in Core Data as Int16).
    func assigneeName(for assignment: MemberAssignment) -> String {
        if assignment.isEveryone { return "Everyone" }
        guard let idx = assignment.memberIndex else { return "Unknown" }
        return memberName(at: idx)
    }

    /// Returns the icon for an assignee value.
    func assigneeIcon(for assignment: MemberAssignment) -> String {
        assignment.systemImage
    }

    /// All possible assignments: Everyone first, then each member.
    var allAssignments: [MemberAssignment] {
        [.everyone] + members.indices.map { MemberAssignment.member($0) }
    }

    // ── Migration from old myName/partnerName format ─────────────────────────

    func migrateFromOldFormat() {
        // If memberNamesRaw is empty but old keys exist, migrate.
        guard memberNamesRaw.isEmpty else { return }
        let oldMy = UserDefaults.standard.string(forKey: "myName") ?? "Me"
        let oldPartner = UserDefaults.standard.string(forKey: "partnerName") ?? "Partner"
        encodeMemberNames([oldMy, oldPartner])
    }

    // ── Shopping: user-addable stores ──────────────────────────────────────────

    static let defaultStores = ["Costco", "Zehrs", "Home Depot", "Walmart", "Amazon"]

    @AppStorage("customStores")
    private var customStoresRaw: String = "" {
        willSet { objectWillChange.send() }
    }

    @AppStorage("hiddenStores")
    private var hiddenStoresRaw: String = "" {
        willSet { objectWillChange.send() }
    }

    @AppStorage("storeIcons")
    private var storeIconsRaw: String = "" {
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

    func addStore(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !stores.contains(trimmed) else { return }
        customStoresRaw += customStoresRaw.isEmpty ? trimmed : ",\(trimmed)"
    }

    func removeStore(_ name: String) {
        let custom = customStoresRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0 != name && !$0.isEmpty }
        customStoresRaw = custom.joined(separator: ",")
        if Self.defaultStores.contains(name) {
            hiddenStoresRaw += hiddenStoresRaw.isEmpty ? name : ",\(name)"
        }
        var icons = decodeIcons(storeIconsRaw)
        icons.removeValue(forKey: name)
        storeIconsRaw = encodeIcons(icons)
    }

    func renameStore(_ oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != oldName else { return }
        removeStore(oldName)
        addStore(trimmed)
        var icons = decodeIcons(storeIconsRaw)
        if let icon = icons[oldName] {
            icons.removeValue(forKey: oldName)
            icons[trimmed] = icon
            storeIconsRaw = encodeIcons(icons)
        }
    }

    func iconForStore(_ name: String) -> String {
        decodeIcons(storeIconsRaw)[name] ?? "storefront.fill"
    }

    func setIconForStore(_ name: String, icon: String) {
        var icons = decodeIcons(storeIconsRaw)
        icons[name] = icon
        storeIconsRaw = encodeIcons(icons)
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

    @AppStorage("itemTypeIcons")
    private var itemTypeIconsRaw: String = "" {
        willSet { objectWillChange.send() }
    }

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

    func addItemType(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !itemTypes.contains(trimmed) else { return }
        customItemTypesRaw += customItemTypesRaw.isEmpty ? trimmed : ",\(trimmed)"
    }

    func removeItemType(_ name: String) {
        let custom = customItemTypesRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0 != name && !$0.isEmpty }
        customItemTypesRaw = custom.joined(separator: ",")
        if Self.defaultItemTypes.contains(name) {
            hiddenItemTypesRaw += hiddenItemTypesRaw.isEmpty ? name : ",\(name)"
        }
        var icons = decodeIcons(itemTypeIconsRaw)
        icons.removeValue(forKey: name)
        itemTypeIconsRaw = encodeIcons(icons)
    }

    func renameItemType(_ oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != oldName else { return }
        removeItemType(oldName)
        addItemType(trimmed)
        var icons = decodeIcons(itemTypeIconsRaw)
        if let icon = icons[oldName] {
            icons.removeValue(forKey: oldName)
            icons[trimmed] = icon
            itemTypeIconsRaw = encodeIcons(icons)
        }
    }

    func iconForItemType(_ name: String) -> String {
        decodeIcons(itemTypeIconsRaw)[name] ?? "tag.fill"
    }

    func setIconForItemType(_ name: String, icon: String) {
        var icons = decodeIcons(itemTypeIconsRaw)
        icons[name] = icon
        itemTypeIconsRaw = encodeIcons(icons)
    }

    // ── JSON helpers ──────────────────────────────────────────────────────────

    private func decodeIcons(_ raw: String) -> [String: String] {
        guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func encodeIcons(_ icons: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(icons) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func decodeMemberNames() -> [String] {
        guard !memberNamesRaw.isEmpty, let data = memberNamesRaw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private func encodeMemberNames(_ names: [String]) {
        guard let data = try? JSONEncoder().encode(names) else { return }
        memberNamesRaw = String(data: data, encoding: .utf8) ?? ""
    }
}
