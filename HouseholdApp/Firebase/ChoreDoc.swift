import Foundation

struct ChoreDoc: Codable, Identifiable {
    var id: String
    var title: String
    var notes: String?
    var assignedToMembers: [Int]   // empty = everyone
    var dueDateType: Int16
    var dueDate: Date?
    var repeatInterval: Int16
    var isCompleted: Bool
    var completedAt: Date?
    var completedByMembers: [Int]
    var categoryId: String?
    var sortOrder: Int32
    var createdAt: Date

    // Computed display helpers (same logic as old CoreDataHelpers)
    var titleSafe: String { title }

    var assignedMemberIndices: Set<Int> {
        get { Set(assignedToMembers) }
        set { assignedToMembers = newValue.sorted() }
    }

    var dueDateTypeEnum: DueDateType {
        get { DueDateType(rawValue: dueDateType) ?? .none }
        set { dueDateType = newValue.rawValue }
    }

    var repeatIntervalEnum: RepeatInterval {
        get { RepeatInterval(rawValue: repeatInterval) ?? .none }
        set { repeatInterval = newValue.rawValue }
    }

    var dueDateLabel: String? {
        let cal = Calendar.current
        switch dueDateTypeEnum {
        case .specificDate:
            guard let date = dueDate else { return nil }
            if cal.isDateInToday(date)     { return "Today" }
            if cal.isDateInTomorrow(date)  { return "Tomorrow" }
            if cal.isDateInYesterday(date) { return "Yesterday" }
            return date.formatted(date: .abbreviated, time: .omitted)
        case .week:
            guard let date = dueDate else { return "This week" }
            if let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now), thisWeek.contains(date) {
                return "This week"
            }
            guard let weekStart = cal.dateInterval(of: .weekOfYear, for: date)?.start else { return "This week" }
            return "Week of \(weekStart.formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            guard let date = dueDate else { return "This month" }
            if let thisMonth = cal.dateInterval(of: .month, for: .now), thisMonth.contains(date) {
                return "This month"
            }
            return date.formatted(.dateTime.month(.wide).year())
        case .none:
            return nil
        }
    }

    private var effectiveDueDate: Date? {
        let cal = Calendar.current
        switch dueDateTypeEnum {
        case .specificDate: return dueDate
        case .week:
            guard let date = dueDate else { return nil }
            return cal.dateInterval(of: .weekOfYear, for: date)?.end
        case .month:
            guard let date = dueDate else { return nil }
            return cal.dateInterval(of: .month, for: date)?.end
        case .none: return nil
        }
    }

    var isOverdue: Bool {
        guard !isCompleted, let effective = effectiveDueDate else { return false }
        return effective < Calendar.current.startOfDay(for: .now)
    }

    var isDueToday: Bool {
        guard !isCompleted, dueDateTypeEnum == .specificDate, let date = dueDate else { return false }
        return Calendar.current.isDateInToday(date)
    }

    var section: ChoreSection {
        if isCompleted { return .completed }
        if isOverdue   { return .overdue }
        if isDueToday  { return .today }
        let cal = Calendar.current
        if let date = dueDate {
            if let week = cal.dateInterval(of: .weekOfYear, for: .now), week.contains(date) { return .thisWeek }
            if let month = cal.dateInterval(of: .month, for: .now), month.contains(date) { return .thisMonth }
            if dueDateTypeEnum != .none { return .upcoming }
        }
        return .noDate
    }
}
