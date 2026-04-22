import Foundation

struct CompletionLogDoc: Codable, Identifiable {
    var id: String
    var choreId: String
    var completedAt: Date
    var completedByMemberIndex: Int
}
