// MealListView.swift
import SwiftUI

struct MealListView: View {

    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var mealStore:     MealStore
    @EnvironmentObject private var householdCtrl: HouseholdController
    @EnvironmentObject private var router:        TabRouter

    @State private var filterIndex     = -2   // -2=All, 0+=member
    @State private var showingAddMeal  = false
    @State private var showingSavedMeals = false
    @State private var showingImport = false
    @State private var mealToEdit: MealDoc? = nil
    @State private var showDeleteAlert = false
    @State private var mealToDelete: MealDoc? = nil

    private var householdId: String { householdCtrl.household?.id ?? "" }

    private var filteredMeals: [MealDoc] {
        guard filterIndex >= 0 else { return mealStore.meals }
        return mealStore.meals.filter {
            $0.assignedToMembers.isEmpty || $0.assignedToMembers.contains(filterIndex)
        }
    }

    /// Meals still to come (today or later) — grouped by day at the top.
    private var upcomingMeals: [MealDoc] { filteredMeals.filter { !$0.isPast } }
    /// Past meals auto-complete and sink to a single section at the bottom,
    /// most recent first.
    private var pastMeals: [MealDoc] {
        filteredMeals.filter(\.isPast).sorted { $0.day > $1.day }
    }

    /// Distinct upcoming days (start-of-day), ascending. Meals are pre-sorted by the store.
    private var days: [Date] {
        var seen = Set<Date>()
        var result: [Date] = []
        for meal in upcomingMeals {
            let d = Calendar.current.startOfDay(for: meal.day)
            if seen.insert(d).inserted { result.append(d) }
        }
        return result
    }

    private func meals(on day: Date) -> [MealDoc] {
        upcomingMeals.filter { Calendar.current.isDate($0.day, inSameDayAs: day) }
    }

    private func dayHeader(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day)    { return "Today" }
        if cal.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                if filteredMeals.isEmpty {
                    if mealStore.meals.isEmpty {
                        ContentUnavailableView("No Meals Planned", systemImage: "fork.knife",
                                              description: Text("Tap + to plan your first meal."))
                    } else {
                        ContentUnavailableView("Nothing Here", systemImage: "line.3.horizontal.decrease.circle",
                                              description: Text("No meals for \(appSettings.memberName(at: filterIndex)). Try the All tab."))
                    }
                } else {
                    List {
                        ForEach(days, id: \.self) { day in
                            Section {
                                ForEach(meals(on: day)) { meal in
                                    MealRowView(meal: meal)
                                        .contentShape(Rectangle())
                                        .onTapGesture { mealToEdit = meal }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                mealToDelete = meal; showDeleteAlert = true
                                            } label: { Label("Delete", systemImage: "trash") }
                                        }
                                }
                            } header: {
                                HStack {
                                    Text(dayHeader(day)).font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Calendar.current.isDateInToday(day) ? .blue : .secondary)
                                    Spacer()
                                    Text("\(meals(on: day).count)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }

                        // Past meals live at the bottom, newest first.
                        if !pastMeals.isEmpty {
                            Section {
                                ForEach(pastMeals) { meal in
                                    MealRowView(meal: meal)
                                        .contentShape(Rectangle())
                                        .onTapGesture { mealToEdit = meal }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                mealToDelete = meal; showDeleteAlert = true
                                            } label: { Label("Delete", systemImage: "trash") }
                                        }
                                }
                            } header: {
                                HStack {
                                    Text("Completed").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(pastMeals.count)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(.compact)
                }
            }
            .navigationTitle("Meals")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingSavedMeals = true } label: {
                        Image(systemName: "text.book.closed").font(.title3)
                    }
                    .accessibilityLabel("My Meals library")
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingImport = true } label: {
                        Image(systemName: "tablecells").font(.title3)
                    }
                    .accessibilityLabel("Plan from spreadsheet")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAddMeal = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                    .accessibilityLabel("Add Meal")
                }
            }
            .sheet(isPresented: $showingAddMeal) { MealFormView(meal: nil) }
            .sheet(isPresented: $showingSavedMeals) { SavedMealsView() }
            .sheet(isPresented: $showingImport)     { MealPlanImportView() }
            .sheet(item: $mealToEdit)            { MealFormView(meal: $0) }
            .alert("Delete Meal?", isPresented: $showDeleteAlert, presenting: mealToDelete) { meal in
                Button("Delete", role: .destructive) {
                    mealStore.delete(meal, householdId: householdId)
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("\"\($0.displayName)\" will be permanently deleted.") }
            .onAppear(perform: handleDeepLink)
            .onChange(of: router.mealToOpen) { _, _ in handleDeepLink() }
            .onChange(of: mealStore.meals.count) { _, _ in handleDeepLink() }
        }
    }

    /// Opens a meal requested from another tab (grocery item badge).
    private func handleDeepLink() {
        guard let id = router.mealToOpen,
              let meal = mealStore.meals.first(where: { $0.id == id }) else { return }
        router.mealToOpen = nil
        mealToEdit = meal
    }

    private var filterBar: some View {
        Picker("Filter", selection: $filterIndex) {
            Text("All").tag(-2)
            ForEach(Array(appSettings.members.indices), id: \.self) { idx in
                Text(appSettings.memberName(at: idx)).tag(idx)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal).padding(.vertical, 5)
        .background(Color(.systemGroupedBackground))
    }

}
