// ShoppingListView.swift
import SwiftUI

enum ShoppingGroupBy: String, CaseIterable {
    case store = "Store"
    case type  = "Type"
}

struct ShoppingListView: View {

    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var shoppingStore: ShoppingStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    @State private var groupBy     = ShoppingGroupBy.store
    @State private var filterIndex = -2
    @State private var showingAddItem    = false
    @State private var itemToEdit: ShoppingItemDoc? = nil
    @State private var showingClearAlert = false

    private var householdId: String { householdCtrl.household?.id ?? "" }

    private var filteredItems: [ShoppingItemDoc] {
        guard filterIndex >= 0 else { return shoppingStore.items }
        return shoppingStore.items.filter {
            $0.assignedToMembers.isEmpty || $0.assignedToMembers.contains(filterIndex)
        }
    }

    private var unpurchased: [ShoppingItemDoc] { filteredItems.filter { !$0.isPurchased } }
    private var purchased:   [ShoppingItemDoc] { filteredItems.filter { $0.isPurchased } }

    private var sectionKeys: [String] {
        let keys: [String]
        switch groupBy {
        case .store: keys = unpurchased.map(\.storeGroupKey)
        case .type:  keys = unpurchased.map(\.typeGroupKey)
        }
        return Array(Set(keys)).sorted()
    }

    private func items(for key: String) -> [ShoppingItemDoc] {
        unpurchased.filter {
            switch groupBy {
            case .store: return $0.storeGroupKey == key
            case .type:  return $0.typeGroupKey == key
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Picker("Group by", selection: $groupBy) {
                        ForEach(ShoppingGroupBy.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Picker("Filter", selection: $filterIndex) {
                        Text("All").tag(-2)
                        ForEach(Array(appSettings.members.indices), id: \.self) { idx in
                            Text(appSettings.memberName(at: idx)).tag(idx)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal).padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))

                if filteredItems.isEmpty {
                    ContentUnavailableView("No Items", systemImage: "cart",
                                          description: Text("Tap + to add your first shopping item."))
                } else {
                    List {
                        ForEach(sectionKeys, id: \.self) { key in
                            Section {
                                ForEach(items(for: key)) { item in
                                    ShoppingRowView(item: item)
                                        .contentShape(Rectangle())
                                        .onTapGesture { itemToEdit = item }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                shoppingStore.delete(item, householdId: householdId)
                                            } label: { Label("Delete", systemImage: "trash") }
                                        }
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                shoppingStore.markPurchased(item, householdId: householdId)
                                            } label: { Label("Got It", systemImage: "checkmark") }
                                            .tint(.green)
                                        }
                                }
                            } header: {
                                HStack {
                                    sectionIcon(for: key)
                                    Text(key).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(items(for: key).count)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }

                        if !purchased.isEmpty {
                            Section {
                                ForEach(purchased) { item in
                                    ShoppingRowView(item: item)
                                        .contentShape(Rectangle())
                                        .onTapGesture { itemToEdit = item }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                shoppingStore.delete(item, householdId: householdId)
                                            } label: { Label("Delete", systemImage: "trash") }
                                        }
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                shoppingStore.markUnpurchased(item, householdId: householdId)
                                            } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                                            .tint(.orange)
                                        }
                                }
                            } header: {
                                HStack {
                                    Text("Purchased").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(purchased.count)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Shopping")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !purchased.isEmpty {
                        Button { showingClearAlert = true } label: { Text("Clear").font(.subheadline) }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAddItem = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingAddItem) { ShoppingFormView(item: nil) }
            .sheet(item: $itemToEdit)            { ShoppingFormView(item: $0) }
            .alert("Clear Purchased Items?", isPresented: $showingClearAlert) {
                Button("Clear All", role: .destructive) {
                    purchased.forEach { shoppingStore.delete($0, householdId: householdId) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This will delete \(purchased.count) purchased item(s).") }
        }
    }

    @ViewBuilder
    private func sectionIcon(for key: String) -> some View {
        switch groupBy {
        case .store: Image(systemName: "storefront").font(.caption).foregroundStyle(.secondary)
        case .type:  AppIcon(name: appSettings.iconForItemType(key), color: .secondary, font: .caption)
        }
    }
}
