// CategoryListView.swift
// HouseholdApp

import SwiftUI

struct CategoryListView: View {

    @EnvironmentObject private var categoryStore: CategoryStore
    @EnvironmentObject private var choreStore:    ChoreStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    @State private var showingAddCategory = false
    @State private var categoryToEdit: CategoryDoc? = nil

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]
    private var householdId: String { householdCtrl.household?.id ?? "" }

    var body: some View {
        NavigationStack {
            Group {
                if categoryStore.categories.isEmpty {
                    ContentUnavailableView(
                        "No Categories",
                        systemImage: "square.grid.2x2",
                        description: Text("Tap + to add your first category.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(categoryStore.categories) { category in
                                categoryCard(category)
                                    .contextMenu {
                                        Button("Edit") { categoryToEdit = category }
                                        Button("Delete", role: .destructive) {
                                            categoryStore.delete(category, householdId: householdId)
                                        }
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Categories")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAddCategory = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingAddCategory) {
                CategoryFormView(category: nil)
            }
            .sheet(item: $categoryToEdit) { cat in
                CategoryFormView(category: cat)
            }
        }
    }

    private func categoryCard(_ category: CategoryDoc) -> some View {
        let color = Color(hex: category.colorHex) ?? .gray
        let pendingCount = choreStore.chores.filter {
            !$0.isCompleted && $0.categoryId == category.id
        }.count

        return Button {
            categoryToEdit = category
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    AppIcon(name: category.iconNameSafe, color: color, font: .title2)
                    Spacer()
                    if pendingCount > 0 {
                        Text("\(pendingCount)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(color, in: Capsule())
                    }
                }
                Text(category.nameSafe)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(color.opacity(0.1))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.3), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}
