// MealPlanImporter.swift
// Turns a filled-out MealPlanTemplate.xlsx into a preview-able import plan:
// meals, shopping items for "to buy" ingredients, trips (created when
// missing), and packing items.
//
// Design rule: NEVER fail the whole file for one bad row. Each row either
// produces documents or an issue with its sheet + row number, and the user
// sees both before anything is written. Duplicates against what's already
// in the household are skipped so re-importing the same file is safe.
//
// Column and sheet matching is deliberately forgiving (case-insensitive,
// punctuation ignored, several header aliases, many date formats) — the
// template locks headers, but a user re-typing them shouldn't break import.
// Keep the aliases here in sync with scripts/make-meal-template.py.

import Foundation

// ── Output ────────────────────────────────────────────────────────────────────

struct ImportIssue: Identifiable {
    enum Level { case error, warning }
    let id = UUID()
    let level: Level
    let sheet: String
    let row: Int?          // 1-based, as shown in the spreadsheet
    let message: String

    var location: String {
        if let row { return "\(sheet) row \(row)" }
        return sheet
    }
}

struct MealPlanImportPlan {
    var newTrips: [TripDoc] = []
    var meals: [MealDoc] = []
    var shoppingItems: [ShoppingItemDoc] = []
    var packingItems: [PackingItemDoc] = []
    var issues: [ImportIssue] = []
    /// Rows understood but skipped because they already exist.
    var duplicatesSkipped = 0

    var errors: [ImportIssue]   { issues.filter { $0.level == .error } }
    var warnings: [ImportIssue] { issues.filter { $0.level == .warning } }
    var hasAnythingToImport: Bool {
        !newTrips.isEmpty || !meals.isEmpty || !shoppingItems.isEmpty || !packingItems.isEmpty
    }
}

// ── Inputs ────────────────────────────────────────────────────────────────────

/// What the importer needs to know about the household to dedupe and link.
struct MealPlanImportContext {
    var members: [String]
    var packingSections: [String]
    var existingTrips: [TripDoc]
    var existingMeals: [MealDoc]
    var existingShopping: [ShoppingItemDoc]
    var existingPacking: [PackingItemDoc]
    var now: Date = Date()
}

// ── Importer ──────────────────────────────────────────────────────────────────

struct MealPlanImporter {

    let context: MealPlanImportContext

    func plan(from workbook: XLSXWorkbook) -> MealPlanImportPlan {
        var plan = MealPlanImportPlan()

        // ── Meals sheet (required) ──────────────────────────────────────────
        guard let mealsSheet = workbook.sheet(named: "Meals")
                ?? workbook.sheets.first(where: { findHeader(in: $0, keys: ["date", "meal"]) != nil })
        else {
            plan.issues.append(ImportIssue(level: .error, sheet: "Workbook", row: nil,
                message: "Couldn't find a Meals sheet. Start from the template so the sheets and headers are recognized."))
            return plan
        }

        let mealRows = parseMeals(mealsSheet, into: &plan)
        let tripRows = workbook.sheet(named: "Trips").map { parseTrips($0, into: &plan) } ?? []
        let packRows = workbook.sheet(named: "Packing").map { parsePacking($0, into: &plan) } ?? []

        // ── Resolve trips referenced anywhere ───────────────────────────────
        var tripIdByKey: [String: String] = [:]
        for t in context.existingTrips { tripIdByKey[key(t.name)] = t.id }

        for row in tripRows {
            let k = key(row.name)
            if tripIdByKey[k] != nil {
                plan.issues.append(ImportIssue(level: .warning, sheet: "Trips", row: row.row,
                    message: "\"\(row.name)\" already exists — using the existing trip."))
                plan.duplicatesSkipped += 1
                continue
            }
            let trip = TripDoc(id: UUID().uuidString, name: row.name,
                               startDate: row.start, endDate: row.end,
                               notes: row.notes, createdAt: context.now)
            plan.newTrips.append(trip)
            tripIdByKey[k] = trip.id
        }

        // Trips named on meals but defined nowhere: create from the meals' dates.
        let mealTripNames = Dictionary(grouping: mealRows.compactMap { r in r.trip.map { ($0, r.day) } },
                                       by: { key($0.0) })
        for (k, refs) in mealTripNames where tripIdByKey[k] == nil {
            let days = refs.map(\.1)
            guard let start = days.min(), let end = days.max() else { continue }
            let trip = TripDoc(id: UUID().uuidString, name: refs[0].0,
                               startDate: start, endDate: end, notes: nil, createdAt: context.now)
            plan.newTrips.append(trip)
            tripIdByKey[k] = trip.id
            plan.issues.append(ImportIssue(level: .warning, sheet: "Meals", row: nil,
                message: "Trip \"\(refs[0].0)\" isn't in the app or on the Trips sheet — creating it spanning \(trip.dateRangeLabel). Edit the dates afterwards if needed."))
        }

        // ── Meals → docs, shopping, food packing ────────────────────────────
        var seenMealKeys = Set<String>(context.existingMeals.map(mealKey))
        var seenShopping = Set<String>(
            context.existingShopping.filter { !$0.isPurchased }.map { key($0.name) })
        var seenPacking = Set<String>(context.existingPacking.map { key($0.tripId + "|" + $0.name) })

        for row in mealRows {
            var meal = MealDoc(
                id: UUID().uuidString, name: row.name, day: row.day,
                mealType: row.type.rawValue,
                assignedToMembers: row.cooks, ingredients: [],
                notes: row.notes, isCompleted: false, completedAt: nil, createdAt: context.now
            )
            meal.recipeURL    = row.recipe
            meal.instructions = row.instructions
            if let t = row.trip { meal.tripId = tripIdByKey[key(t)] }

            let mk = mealKey(meal)
            if seenMealKeys.contains(mk) {
                plan.duplicatesSkipped += 1
                plan.issues.append(ImportIssue(level: .warning, sheet: "Meals", row: row.row,
                    message: "\(meal.displayName) on \(meal.dayLabel) already exists — skipped."))
                continue
            }
            seenMealKeys.insert(mk)

            // Ingredients on hand, then ones to buy (each → shopping item).
            meal.ingredients = row.have.map { MealIngredient(name: $0, have: true) }
            for name in row.buy {
                var ing = MealIngredient(name: name, have: false)
                let sk = key(name)
                if seenShopping.contains(sk) {
                    // Already on the list from another meal or earlier — link only.
                    ing.addedToList = true
                } else {
                    seenShopping.insert(sk)
                    ing.addedToList = true
                    plan.shoppingItems.append(ShoppingItemDoc(
                        id: UUID().uuidString, name: name, quantity: nil, store: nil, itemType: "Food",
                        assignedToMembers: [], isPurchased: false, purchasedAt: nil, notes: nil,
                        sortOrder: 0, createdAt: context.now,
                        mealId: meal.id, mealName: meal.displayName))
                }
                meal.ingredients.append(ing)
            }

            // Trip meals: every ingredient goes on the packing list under Food
            // (mirrors MealFormView.syncIngredientsToPackingList).
            if let tripId = meal.tripId {
                for ing in meal.ingredients {
                    let pk = key(tripId + "|" + ing.name)
                    guard !seenPacking.contains(pk) else { continue }
                    seenPacking.insert(pk)
                    plan.packingItems.append(PackingItemDoc(
                        id: UUID().uuidString, tripId: tripId, name: ing.name, section: "Food",
                        isPacked: false, packedAt: nil, createdAt: context.now, mealId: meal.id))
                }
            }

            plan.meals.append(meal)
        }

        // ── Explicit packing rows ───────────────────────────────────────────
        for row in packRows {
            guard let tripId = tripIdByKey[key(row.trip)] else {
                plan.issues.append(ImportIssue(level: .error, sheet: "Packing", row: row.row,
                    message: "Trip \"\(row.trip)\" not found. Add it on the Trips sheet or name it on a meal."))
                continue
            }
            let pk = key(tripId + "|" + row.item)
            if seenPacking.contains(pk) {
                plan.duplicatesSkipped += 1
                continue
            }
            seenPacking.insert(pk)
            plan.packingItems.append(PackingItemDoc(
                id: UUID().uuidString, tripId: tripId, name: row.item, section: row.section,
                isPacked: false, packedAt: nil, createdAt: context.now, mealId: nil))
        }

        return plan
    }

    // ── Row parsing ────────────────────────────────────────────────────────────

    private struct MealRow {
        let row: Int; let day: Date; let type: MealType; let name: String?
        let cooks: [Int]; let have: [String]; let buy: [String]
        let trip: String?; let recipe: String?; let instructions: String?; let notes: String?
    }
    private struct TripRow { let row: Int; let name: String; let start: Date; let end: Date; let notes: String? }
    private struct PackRow { let row: Int; let trip: String; let item: String; let section: String }

    private static let mealAliases: [String: [String]] = [
        "date":  ["date", "day", "when"],
        "type":  ["meal", "mealtype", "type"],
        "name":  ["mealname", "name", "dish", "title"],
        "cook":  ["cook", "cooks", "who", "assignedto", "member", "madeby"],
        "have":  ["ingredientshave", "ingredients", "have", "onhand"],
        "buy":   ["ingredientstobuy", "tobuy", "buy", "needtobuy", "shopping", "missing", "need"],
        "trip":  ["tripname", "trip", "event"],
        "recipe":["recipelink", "recipe", "link", "url"],
        "instructions": ["instructions", "steps", "directions", "method"],
        "notes": ["notes", "note", "comments"],
    ]
    private static let tripAliases: [String: [String]] = [
        "name":  ["tripname", "trip", "name", "event"],
        "start": ["startdate", "start", "from", "begins"],
        "end":   ["enddate", "end", "to", "until", "ends"],
        "notes": ["notes", "note"],
    ]
    private static let packAliases: [String: [String]] = [
        "trip":    ["tripname", "trip", "event"],
        "item":    ["item", "name", "what", "packingitem"],
        "section": ["section", "category", "group"],
    ]

    private func parseMeals(_ sheet: XLSXSheet, into plan: inout MealPlanImportPlan) -> [MealRow] {
        guard let (headerRow, cols) = findHeader(in: sheet, aliases: Self.mealAliases, required: ["date", "type"]) else {
            plan.issues.append(ImportIssue(level: .error, sheet: "Meals", row: nil,
                message: "Couldn't find the header row (needs at least Date and Meal columns)."))
            return []
        }
        var out: [MealRow] = []
        for r in (headerRow + 1)..<max(headerRow + 1, sheet.rows.count) {
            guard !isBlankRow(sheet, r) else { continue }
            let rowNo = r + 1
            let dateCell = cols["date"].flatMap { sheet.cell(r, $0) }
            let typeText = text(sheet, r, cols["type"])

            guard let day = parseDate(dateCell) else {
                plan.issues.append(ImportIssue(level: .error, sheet: "Meals", row: rowNo,
                    message: "Date is missing or not understood (\"\(dateCell?.stringValue ?? "")\"). Use e.g. 2026-09-14."))
                continue
            }
            guard let type = parseMealType(typeText) else {
                plan.issues.append(ImportIssue(level: .error, sheet: "Meals", row: rowNo,
                    message: typeText.isEmpty ? "Meal type is required (Breakfast, Lunch, Dinner…)."
                                              : "Meal type \"\(typeText)\" isn't recognized."))
                continue
            }

            let (cooks, unknown) = parseMembers(text(sheet, r, cols["cook"]))
            for u in unknown {
                plan.issues.append(ImportIssue(level: .warning, sheet: "Meals", row: rowNo,
                    message: "Cook \"\(u)\" doesn't match a household member — left as everyone."))
            }
            let recipe = optional(text(sheet, r, cols["recipe"]))
            if let recipe, URL(string: recipe)?.scheme == nil {
                plan.issues.append(ImportIssue(level: .warning, sheet: "Meals", row: rowNo,
                    message: "Recipe link \"\(recipe)\" doesn't look like a web address; kept as typed."))
            }

            out.append(MealRow(
                row: rowNo, day: day, type: type,
                name: optional(text(sheet, r, cols["name"])),
                cooks: cooks,
                have: splitList(text(sheet, r, cols["have"])),
                buy: splitList(text(sheet, r, cols["buy"])),
                trip: optional(text(sheet, r, cols["trip"])),
                recipe: recipe,
                instructions: optional(text(sheet, r, cols["instructions"])),
                notes: optional(text(sheet, r, cols["notes"]))))
        }
        return out
    }

    private func parseTrips(_ sheet: XLSXSheet, into plan: inout MealPlanImportPlan) -> [TripRow] {
        guard let (headerRow, cols) = findHeader(in: sheet, aliases: Self.tripAliases, required: ["name"]) else {
            return []   // sheet present but empty/unrecognized — fine, it's optional
        }
        var out: [TripRow] = []
        var seen = Set<String>()
        for r in (headerRow + 1)..<max(headerRow + 1, sheet.rows.count) {
            guard !isBlankRow(sheet, r) else { continue }
            let rowNo = r + 1
            let name = text(sheet, r, cols["name"])
            guard !name.isEmpty else {
                plan.issues.append(ImportIssue(level: .error, sheet: "Trips", row: rowNo, message: "Trip Name is required."))
                continue
            }
            let start = parseDate(cols["start"].flatMap { sheet.cell(r, $0) })
            let end   = parseDate(cols["end"].flatMap { sheet.cell(r, $0) })
            guard let start else {
                plan.issues.append(ImportIssue(level: .error, sheet: "Trips", row: rowNo, message: "Start Date is missing or not understood."))
                continue
            }
            let endResolved = end ?? start
            if end == nil {
                plan.issues.append(ImportIssue(level: .warning, sheet: "Trips", row: rowNo, message: "End Date missing — using the start date."))
            }
            if endResolved < start {
                plan.issues.append(ImportIssue(level: .error, sheet: "Trips", row: rowNo, message: "End Date is before Start Date."))
                continue
            }
            if !seen.insert(key(name)).inserted {
                plan.issues.append(ImportIssue(level: .warning, sheet: "Trips", row: rowNo, message: "\"\(name)\" is listed twice — using the first."))
                continue
            }
            out.append(TripRow(row: rowNo, name: name, start: start, end: endResolved,
                               notes: optional(text(sheet, r, cols["notes"]))))
        }
        return out
    }

    private func parsePacking(_ sheet: XLSXSheet, into plan: inout MealPlanImportPlan) -> [PackRow] {
        guard let (headerRow, cols) = findHeader(in: sheet, aliases: Self.packAliases, required: ["trip", "item"]) else {
            return []
        }
        var out: [PackRow] = []
        for r in (headerRow + 1)..<max(headerRow + 1, sheet.rows.count) {
            guard !isBlankRow(sheet, r) else { continue }
            let rowNo = r + 1
            let trip = text(sheet, r, cols["trip"])
            let item = text(sheet, r, cols["item"])
            guard !trip.isEmpty, !item.isEmpty else {
                plan.issues.append(ImportIssue(level: .error, sheet: "Packing", row: rowNo,
                    message: trip.isEmpty ? "Trip Name is required." : "Item is required."))
                continue
            }
            let rawSection = text(sheet, r, cols["section"])
            let section: String
            if rawSection.isEmpty {
                section = "Other"
            } else if let match = context.packingSections.first(where: { key($0) == key(rawSection) }) {
                section = match
            } else {
                section = "Other"
                plan.issues.append(ImportIssue(level: .warning, sheet: "Packing", row: rowNo,
                    message: "Section \"\(rawSection)\" isn't one of yours — filed under Other."))
            }
            out.append(PackRow(row: rowNo, trip: trip, item: item, section: section))
        }
        return out
    }

    // ── Header detection ───────────────────────────────────────────────────────

    /// Scans the first rows for one whose cells match enough known headers.
    /// Returns the row index and a map of logical field → column index.
    private func findHeader(in sheet: XLSXSheet, aliases: [String: [String]],
                            required: [String]) -> (Int, [String: Int])? {
        for r in 0..<min(sheet.rows.count, 10) {
            var map: [String: Int] = [:]
            for (c, cell) in sheet.rows[r].enumerated() {
                guard let cell, case .text(let raw) = cell else { continue }
                let norm = XLSXWorkbook.normalize(raw)
                guard !norm.isEmpty else { continue }
                for (field, names) in aliases where map[field] == nil && names.contains(norm) {
                    map[field] = c
                    break
                }
            }
            if required.allSatisfy({ map[$0] != nil }) { return (r, map) }
        }
        return nil
    }

    private func findHeader(in sheet: XLSXSheet, keys: [String]) -> Int? {
        findHeader(in: sheet, aliases: Self.mealAliases, required: keys)?.0
    }

    // ── Cell helpers ───────────────────────────────────────────────────────────

    private func text(_ sheet: XLSXSheet, _ r: Int, _ c: Int?) -> String {
        guard let c, let cell = sheet.cell(r, c) else { return "" }
        return cell.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func optional(_ s: String) -> String? { s.isEmpty ? nil : s }

    private func isBlankRow(_ sheet: XLSXSheet, _ r: Int) -> Bool {
        guard r < sheet.rows.count else { return true }
        return sheet.rows[r].allSatisfy { $0 == nil || $0!.isBlank }
    }

    private func splitList(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
         .map { $0.trimmingCharacters(in: .whitespaces) }
         .filter { !$0.isEmpty }
    }

    private func key(_ s: String) -> String { XLSXWorkbook.normalize(s) }

    private func mealKey(_ m: MealDoc) -> String {
        let day = Calendar.current.startOfDay(for: m.day).timeIntervalSince1970
        return "\(Int(day))|\(m.mealType)|\(key(m.displayName))"
    }

    // ── Value parsing ──────────────────────────────────────────────────────────

    private func parseMealType(_ s: String) -> MealType? {
        let k = key(s)
        guard !k.isEmpty else { return nil }
        if let exact = MealType.allCases.first(where: { $0.rawValue == k }) { return exact }
        if k == "supper" || k == "tea" { return .dinner }
        if k == "morning" { return .breakfast }
        if k == "sweet" || k == "pudding" { return .dessert }
        // Prefix match: "din" → dinner, "break" → breakfast.
        return MealType.allCases.first { $0.rawValue.hasPrefix(k) || k.hasPrefix($0.rawValue) }
    }

    /// Returns matched member indices and any names that didn't match.
    private func parseMembers(_ s: String) -> ([Int], [String]) {
        let k = key(s)
        if k.isEmpty || k == "everyone" || k == "all" || k == "both" || k == "anyone" { return ([], []) }
        var found: [Int] = []
        var unknown: [String] = []
        let parts = s.replacingOccurrences(of: " and ", with: ",")
                     .replacingOccurrences(of: "&", with: ",")
                     .split(separator: ",")
                     .map { $0.trimmingCharacters(in: .whitespaces) }
                     .filter { !$0.isEmpty }
        for part in parts {
            let pk = key(part)
            if let idx = context.members.firstIndex(where: { key($0) == pk }) {
                found.append(idx)
            } else if let idx = context.members.firstIndex(where: { key($0).hasPrefix(pk) || pk.hasPrefix(key($0)) }),
                      !pk.isEmpty {
                found.append(idx)   // "Jord" → Jordan
            } else {
                unknown.append(part)
            }
        }
        // Naming every member is the same as "everyone".
        if Set(found).count == context.members.count { return ([], unknown) }
        return (Array(Set(found)).sorted(), unknown)
    }

    private static let dateFormats = [
        "yyyy-MM-dd", "yyyy/MM/dd", "M/d/yyyy", "M/d/yy", "d-MMM-yyyy",
        "MMM d, yyyy", "MMMM d, yyyy", "MMM d yyyy", "MMMM d yyyy",
        "d MMM yyyy", "d MMMM yyyy", "EEEE MMM d", "EEE MMM d",
        "MMM d", "MMMM d", "d MMM", "M/d",
    ]

    /// Excel serial numbers, ISO strings, and common typed forms. Formats
    /// without a year assume the current year.
    private func parseDate(_ cell: XLSXCell?) -> Date? {
        guard let cell else { return nil }
        let cal = Calendar.current
        switch cell {
        case .number(let serial):
            // Excel epoch: day 1 = 1900-01-01, with the 1900 leap-year bug,
            // so day 0 == 1899-12-30. Serial 25569 == 1970-01-01.
            guard serial > 0, serial < 200_000 else { return nil }
            var comps = DateComponents(year: 1899, month: 12, day: 30)
            comps.calendar = cal
            guard let epoch = comps.date else { return nil }
            return cal.date(byAdding: .day, value: Int(serial), to: cal.startOfDay(for: epoch))
        case .bool:
            return nil
        case .text(let raw):
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { return nil }
            let lower = s.lowercased()
            if lower == "today" { return cal.startOfDay(for: context.now) }
            if lower == "tomorrow" { return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: context.now)) }

            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = cal.timeZone
            f.isLenient = true
            for fmt in Self.dateFormats {
                f.dateFormat = fmt
                guard let d = f.date(from: s) else { continue }
                var result = d
                // Year-less formats parse as year 2000 in POSIX; move to this year.
                if !fmt.contains("y") {
                    let md = cal.dateComponents([.month, .day], from: d)
                    var c = cal.dateComponents([.year], from: context.now)
                    c.month = md.month; c.day = md.day
                    guard let thisYear = cal.date(from: c) else { return nil }
                    result = thisYear
                }
                return cal.startOfDay(for: result)
            }
            // Last resort: the system detector ("next Friday", "Sept 14th").
            if let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
               let m = det.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
               let d = m.date {
                return cal.startOfDay(for: d)
            }
            return nil
        }
    }
}
