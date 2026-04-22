// RootView.swift
import SwiftUI

struct RootView: View {
    @AppStorage("selectedTab") private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ChoreListView()
                .tabItem { Label("Chores", systemImage: "checkmark.circle.fill") }
                .tag(0)
            ShoppingListView()
                .tabItem { Label("Shopping", systemImage: "cart.fill") }
                .tag(1)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(2)
        }
        .tint(.accentColor)
    }
}
