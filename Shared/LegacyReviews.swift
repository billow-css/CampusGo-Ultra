import Foundation

/// Read/write compatibility for existing backups only. There is no active rating feature.
struct LegacyReviewRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var courseKey: String?
    var title: String
    var courseScore: Int?
    var teacherScore: Int?
    var comment = ""
    var teacherComment = ""
    var createdAt = Date()
    var updatedAt = Date()
}
