import Foundation

struct CategoryDoc: Codable, Identifiable {
    var id: String
    var name: String
    var colorHex: String
    var iconName: String
    var sortOrder: Int32

    var nameSafe: String     { name }
    var iconNameSafe: String { iconName }
    var colorSafe: String    { colorHex }

    init(id: String = UUID().uuidString, name: String, colorHex: String, iconName: String, sortOrder: Int32 = 0) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.iconName = iconName
        self.sortOrder = sortOrder
    }
}
