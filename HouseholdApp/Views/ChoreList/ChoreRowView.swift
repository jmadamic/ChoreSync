// ChoreRowView.swift
import SwiftUI

struct ChoreRowView: View {

    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var choreStore:    ChoreStore
    @EnvironmentObject private var categoryStore: CategoryStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    let chore: ChoreDoc
    @State private var checkAnimating = false

    private var householdId: String { householdCtrl.household?.id ?? "" }
    private var category: CategoryDoc? {
        guard let cid = chore.categoryId else { return nil }
        return categoryStore.categories.first { $0.id == cid }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            completionButton
            VStack(alignment: .leading, spacing: 4) {
                Text(chore.titleSafe)
                    .font(.body)
                    .strikethrough(chore.isCompleted, color: .secondary)
                    .foregroundStyle(chore.isCompleted ? .secondary : .primary)
                HStack(spacing: 6) {
                    if let cat = category { categoryBadge(for: cat) }
                    if chore.repeatIntervalEnum != .none { repeatBadge }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let label = chore.dueDateLabel {
                    Text(label).font(.caption)
                        .foregroundStyle(chore.isOverdue ? .red : .secondary)
                }
                assigneeView
            }
        }
        .padding(.vertical, 2)
        .opacity(chore.isCompleted ? 0.6 : 1.0)
    }

    private var completionButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { checkAnimating = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                checkAnimating = false
                if chore.isCompleted {
                    choreStore.markIncomplete(chore, householdId: householdId)
                } else {
                    choreStore.markComplete(chore, byMemberIndex: 0, householdId: householdId)
                }
            }
        } label: {
            Image(systemName: chore.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(chore.isCompleted ? .green : .secondary)
                .scaleEffect(checkAnimating ? 1.3 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private func categoryBadge(for cat: CategoryDoc) -> some View {
        let color = Color(hex: cat.colorHex) ?? .gray
        return AppIconLabel(title: cat.nameSafe, icon: cat.iconNameSafe, color: color)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var repeatBadge: some View {
        Label(chore.repeatIntervalEnum.label, systemImage: "repeat")
            .font(.caption2).foregroundStyle(.secondary)
    }

    private var assigneeView: some View {
        let indices = chore.assignedToMembers.sorted()
        return Group {
            if indices.isEmpty {
                Image(systemName: "person.2.fill").font(.caption).foregroundStyle(.purple)
            } else if indices.count == 1, let idx = indices.first {
                Image(systemName: "person.fill").font(.caption)
                    .foregroundStyle(appSettings.memberColor(at: idx))
            } else {
                HStack(spacing: 3) {
                    ForEach(indices.prefix(3), id: \.self) { idx in
                        Circle().fill(appSettings.memberColor(at: idx)).frame(width: 7, height: 7)
                    }
                    if indices.count > 3 {
                        Text("+\(indices.count - 3)").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
