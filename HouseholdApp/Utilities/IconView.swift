// IconView.swift
// HouseholdApp
//
// Shared icon rendering + picker that supports both SF Symbols and emoji.
// Use AppIcon / AppIconLabel anywhere you'd use Image(systemName:) / Label(_, systemImage:).
// Use IconPickerSection inside a Form to let users choose an icon.

import SwiftUI

// ── Detection ─────────────────────────────────────────────────────────────────

extension String {
    /// True when this string is an emoji/unicode character rather than an SF Symbol name.
    /// SF Symbol names are pure ASCII (letters, digits, dots, hyphens), so any
    /// non-ASCII scalar means it's an emoji.
    var isEmojiIcon: Bool {
        unicodeScalars.contains { $0.value > 127 }
    }
}

// ── AppIcon ───────────────────────────────────────────────────────────────────

/// Renders either an emoji (Text) or an SF Symbol (Image), depending on the name.
struct AppIcon: View {
    let name: String
    var color: Color = .primary
    var font: Font = .body

    var body: some View {
        if name.isEmojiIcon {
            Text(name).font(font)
        } else {
            Image(systemName: name).font(font).foregroundStyle(color)
        }
    }
}

// ── AppIconLabel ──────────────────────────────────────────────────────────────

/// Drop-in replacement for Label(title, systemImage:) that supports emoji icons.
struct AppIconLabel: View {
    let title: String
    let icon: String
    var color: Color = .primary

    var body: some View {
        Label {
            Text(title)
        } icon: {
            AppIcon(name: icon, color: color)
        }
    }
}

// ── IconPickerSection ─────────────────────────────────────────────────────────

/// A Form Section containing a Symbols / Emoji segmented picker + grid.
/// Bind `iconName` — it holds either an SF Symbol name or an emoji string.
struct IconPickerSection: View {
    @Binding var iconName: String
    var accentColor: Color = .blue

    @State private var tab: IconTab = .symbols

    enum IconTab: Hashable { case symbols, emoji }

    // ── SF Symbol list ────────────────────────────────────────────────────────
    static let sfSymbolOptions: [String] = [
        "fork.knife",   "cup.and.saucer.fill", "trash.fill",       "washer.fill",
        "shower",       "bed.double.fill",      "sofa.fill",        "chair.fill",
        "cart.fill",    "leaf.fill",            "figure.walk",      "car.fill",
        "house.fill",   "envelope.fill",        "phone.fill",       "pawprint.fill",
        "wrench.fill",  "lightbulb.fill",       "paintbrush.fill",  "scissors",
        "hammer.fill",  "archivebox.fill",      "bag.fill",         "star.fill",
    ]

    // ── Emoji list ────────────────────────────────────────────────────────────
    static let emojiOptions: [String] = [
        // Household & cleaning
        "🏠", "🛁", "🚿", "🪥", "🧹", "🧺", "🧻", "🧼", "🪣", "🧯",
        // Kitchen
        "🍽️", "🥘", "☕", "🍳", "🧊", "🫖",
        // Home items
        "🛏️", "🛋️", "🪑", "🚪", "🪟", "🔑",
        // Food & grocery
        "🍎", "🥦", "🥛", "🧀", "🥩", "🍞", "🥚", "🧈", "🥕", "🍋",
        // Shopping
        "🛍️", "🏪", "🏬", "📦", "🎁",
        // Tools & maintenance
        "🔧", "🔨", "🪛", "🔩", "⚙️", "🪜", "🔦", "💡", "🔋", "🪝",
        // Nature & outdoor
        "🌿", "🌱", "🌻", "🌳", "☀️", "🌙", "⭐", "🍂", "🌸",
        // Transport
        "🚗", "🚲", "✈️", "⛽",
        // Health & personal
        "💊", "💪", "🧴", "🩺",
        // Misc
        "❤️", "🎉", "📋", "🗑️", "📝", "💰", "🎯", "🏆",
    ]

    var body: some View {
        Section("Icon") {
            Picker("", selection: $tab) {
                Text("Symbols").tag(IconTab.symbols)
                Text("Emoji").tag(IconTab.emoji)
            }
            .pickerStyle(.segmented)

            if tab == .symbols {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 6),
                    spacing: 14
                ) {
                    ForEach(Self.sfSymbolOptions, id: \.self) { icon in
                        Image(systemName: icon)
                            .font(.title3)
                            .foregroundStyle(iconName == icon ? .white : accentColor)
                            .frame(width: 40, height: 40)
                            .background(
                                iconName == icon ? accentColor : accentColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .onTapGesture { iconName = icon }
                    }
                }
                .padding(.vertical, 4)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 7),
                    spacing: 10
                ) {
                    ForEach(Self.emojiOptions, id: \.self) { emoji in
                        Text(emoji)
                            .font(.title3)
                            .frame(width: 38, height: 38)
                            .background(
                                iconName == emoji
                                    ? accentColor.opacity(0.25)
                                    : accentColor.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(iconName == emoji ? accentColor : .clear, lineWidth: 2)
                            )
                            .onTapGesture { iconName = emoji }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .onAppear {
            tab = iconName.isEmojiIcon ? .emoji : .symbols
        }
        .onChange(of: iconName) { _, new in
            // Keep tab in sync if icon is changed from outside (e.g. onAppear populate)
            let expected: IconTab = new.isEmojiIcon ? .emoji : .symbols
            if tab != expected { tab = expected }
        }
    }
}
