// ShoppingRowView.swift
import SwiftUI

struct ShoppingRowView: View {

    @EnvironmentObject private var appSettings:   AppSettings
    @EnvironmentObject private var shoppingStore: ShoppingStore
    @EnvironmentObject private var householdCtrl: HouseholdController

    let item: ShoppingItemDoc
    @State private var checkAnimating = false

    private var householdId: String { householdCtrl.household?.id ?? "" }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { checkAnimating = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    checkAnimating = false
                    if item.isPurchased {
                        shoppingStore.markUnpurchased(item, householdId: householdId)
                    } else {
                        shoppingStore.markPurchased(item, householdId: householdId)
                    }
                }
            } label: {
                Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isPurchased ? .green : .secondary)
                    .scaleEffect(checkAnimating ? 1.3 : 1.0)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.nameSafe)
                        .font(.body)
                        .strikethrough(item.isPurchased, color: .secondary)
                        .foregroundStyle(item.isPurchased ? .secondary : .primary)
                    if let qty = item.quantitySafe {
                        Text(qty).font(.caption2.weight(.medium)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.blue.opacity(0.7), in: Capsule())
                    }
                }
                if let t = item.itemType, !t.isEmpty {
                    AppIconLabel(title: t, icon: appSettings.iconForItemType(t))
                        .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let store = item.store, !store.isEmpty {
                    Text(store).font(.caption).foregroundStyle(.secondary)
                }
                assigneeView
            }
        }
        .padding(.vertical, 2)
        .opacity(item.isPurchased ? 0.6 : 1.0)
    }

    private var assigneeView: some View {
        let indices = item.assignedToMembers.sorted()
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
                        Text("+\(indices.count-3)").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
