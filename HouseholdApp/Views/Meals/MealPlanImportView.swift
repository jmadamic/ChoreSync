// MealPlanImportView.swift
// "Plan from a spreadsheet": hand out the template, take a filled-in
// .xlsx back, show exactly what will be created (and every row that
// couldn't be), then write it all in one go.
//
// Nothing is written until the user taps Import on the preview, and rows
// with errors are simply left out — the rest still import.

import SwiftUI
import UniformTypeIdentifiers

struct MealPlanImportView: View {

    @Environment(\.dismiss)           private var dismiss
    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var mealStore:     MealStore
    @EnvironmentObject private var shoppingStore: ShoppingStore
    @EnvironmentObject private var tripStore:     TripStore
    @EnvironmentObject private var packingStore:  PackingStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    @State private var showingPicker = false
    @State private var plan: MealPlanImportPlan? = nil
    @State private var fileName = ""
    @State private var readError: String? = nil
    @State private var imported = false
    @State private var isImporting = false

    private var householdId: String { householdCtrl.household?.id ?? "" }

    private var templateURL: URL? {
        Bundle.main.url(forResource: "MealPlanTemplate", withExtension: "xlsx")
    }

    private static let xlsxTypes: [UTType] = {
        var types: [UTType] = [.spreadsheet, .data]
        if let x = UTType("org.openxmlformats.spreadsheetml.sheet") { types.insert(x, at: 0) }
        if let x = UTType(filenameExtension: "xlsx") { types.insert(x, at: 0) }
        return types
    }()

    var body: some View {
        NavigationStack {
            Form {
                if imported {
                    doneSection
                } else if let plan {
                    previewSections(plan)
                } else {
                    templateSection
                    importSection
                }
            }
            .navigationTitle("Plan from Spreadsheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(imported ? "Done" : "Cancel") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showingPicker, allowedContentTypes: Self.xlsxTypes) { result in
                handlePicked(result)
            }
        }
    }

    // ── Step 1: template ───────────────────────────────────────────────────────

    private var templateSection: some View {
        Section {
            if let url = templateURL {
                ShareLink(item: url, preview: SharePreview("Meal Plan Template", image: Image(systemName: "tablecells"))) {
                    Label("Get the Template", systemImage: "square.and.arrow.up")
                }
            } else {
                Text("Template not bundled in this build.").foregroundStyle(.secondary)
            }
        } header: {
            Text("1. Fill out the template")
        } footer: {
            Text("Share it to Files, Google Drive, Mail, or AirDrop, then open it in Excel, Google Sheets, or Numbers. One row per meal; Trips and Packing sheets are optional. Headers show what's required, and the Instructions sheet has examples.")
        }
    }

    // ── Step 2: import ─────────────────────────────────────────────────────────

    private var importSection: some View {
        Section {
            Button {
                readError = nil
                showingPicker = true
            } label: {
                Label("Choose a Filled-In File…", systemImage: "doc.badge.arrow.up")
            }
            if let readError {
                Text(readError).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("2. Import it")
        } footer: {
            Text("Save as .xlsx (Google Sheets: File › Download › Microsoft Excel). You'll see a preview before anything is added. Meals, shopping items, trips, and packing items that already exist are skipped, so importing the same file twice is safe.")
        }
    }

    // ── Preview ────────────────────────────────────────────────────────────────

    @ViewBuilder
    private func previewSections(_ plan: MealPlanImportPlan) -> some View {
        Section {
            countRow("Meals", plan.meals.count, "fork.knife")
            countRow("Shopping items", plan.shoppingItems.count, "cart.fill")
            countRow("New trips", plan.newTrips.count, "suitcase.rolling.fill")
            countRow("Packing items", plan.packingItems.count, "checklist")
            if plan.duplicatesSkipped > 0 {
                Label("\(plan.duplicatesSkipped) already exist — skipped", systemImage: "arrow.uturn.backward")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        } header: {
            Text("Will be added from \(fileName)")
        }

        if !plan.meals.isEmpty {
            Section("Meals") {
                ForEach(plan.meals) { meal in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Label(meal.displayName, systemImage: meal.mealTypeEnum.icon)
                            Spacer()
                            Text(meal.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        let buy = meal.ingredients.filter { !$0.have }.count
                        if !meal.ingredients.isEmpty || meal.tripId != nil {
                            Text([
                                meal.ingredients.isEmpty ? nil : "\(meal.ingredients.count) ingredients",
                                buy > 0 ? "\(buy) to buy" : nil,
                                meal.tripId != nil ? "on a trip" : nil
                            ].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        if !plan.errors.isEmpty {
            Section {
                ForEach(plan.errors) { issueRow($0, color: .red) }
            } header: {
                Text("Won't be imported")
            } footer: {
                Text("Fix these rows in the spreadsheet and import again; everything else can go in now.")
            }
        }

        if !plan.warnings.isEmpty {
            Section("Heads up") {
                ForEach(plan.warnings) { issueRow($0, color: .orange) }
            }
        }

        Section {
            Button {
                performImport(plan)
            } label: {
                HStack {
                    Spacer()
                    if isImporting { ProgressView() } else { Text("Import").fontWeight(.semibold) }
                    Spacer()
                }
            }
            .disabled(!plan.hasAnythingToImport || isImporting)

            Button("Choose a Different File") {
                self.plan = nil
                showingPicker = true
            }
        } footer: {
            if !plan.hasAnythingToImport {
                Text("Nothing new to add from this file.")
            }
        }
    }

    private func countRow(_ label: String, _ count: Int, _ icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            Text("\(count)")
                .foregroundStyle(count == 0 ? .secondary : .primary)
                .fontWeight(count == 0 ? .regular : .semibold)
        }
    }

    private func issueRow(_ issue: ImportIssue, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(issue.location).font(.caption.weight(.semibold)).foregroundStyle(color)
            Text(issue.message).font(.subheadline)
        }
    }

    // ── Done ───────────────────────────────────────────────────────────────────

    private var doneSection: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                Text("Imported").font(.headline)
                if let plan {
                    Text("\(plan.meals.count) meals, \(plan.shoppingItems.count) shopping items, \(plan.newTrips.count) trips, \(plan.packingItems.count) packing items.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical)
        }
    }

    // ── Actions ────────────────────────────────────────────────────────────────

    private func handlePicked(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            readError = error.localizedDescription
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let workbook = try XLSXReader.read(data)
                let context = MealPlanImportContext(
                    members: appSettings.members,
                    packingSections: appSettings.packingSections,
                    existingTrips: tripStore.trips,
                    existingMeals: mealStore.meals,
                    existingShopping: shoppingStore.items,
                    existingPacking: packingStore.items)
                fileName = url.lastPathComponent
                plan = MealPlanImporter(context: context).plan(from: workbook)
            } catch {
                readError = error.localizedDescription
            }
        }
    }

    /// Writes in dependency order so links resolve: trips → meals →
    /// shopping (mealId) → packing (tripId, mealId).
    private func performImport(_ plan: MealPlanImportPlan) {
        guard !householdId.isEmpty else {
            readError = "No household yet — open Settings to create or join one first."
            return
        }
        isImporting = true
        for trip in plan.newTrips      { tripStore.save(trip, householdId: householdId) }
        for meal in plan.meals         { mealStore.save(meal, householdId: householdId) }
        for item in plan.shoppingItems { shoppingStore.save(item, householdId: householdId) }
        for item in plan.packingItems  { packingStore.save(item, householdId: householdId) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        isImporting = false
        imported = true
    }
}
