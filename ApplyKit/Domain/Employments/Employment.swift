import Foundation

struct Employment: Identifiable, Codable, Hashable {
    var id: UUID
    var companyName: String
    var role: String
    var location: String
    var startDate: Date?
    var endDate: Date?
    var displayOrder: Int
    var experienceTypeRaw: String
    var referenceURL: String
    var notes: String
    var roleDescription: String
    var createdAt: Date
    var updatedAt: Date

    init(
        companyName: String = "",
        role: String = "",
        location: String = "",
        startDate: Date? = nil,
        endDate: Date? = nil,
        displayOrder: Int = 0,
        experienceType: ExperienceCategory = .work,
        referenceURL: String = "",
        notes: String = "",
        roleDescription: String = ""
    ) {
        self.id = UUID()
        self.companyName = companyName
        self.role = role
        self.location = location
        self.startDate = startDate
        self.endDate = endDate
        self.displayOrder = displayOrder
        self.experienceTypeRaw = experienceType.rawValue
        self.referenceURL = referenceURL
        self.notes = notes
        self.roleDescription = roleDescription
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

extension Employment {
    static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    var displayTitle: String {
        let t = companyName.trimmed
        return t.isEmpty ? "Untitled Employment" : t
    }

    var summaryLine: String {
        let parts = [companyName.trimmed, role.trimmed].filter { !$0.isEmpty }
        let head = parts.joined(separator: " - ")
        let range = dateRangeText()
        return range.isEmpty ? head : "\(head)  (\(range))"
    }

    var experienceCategory: ExperienceCategory {
        ExperienceCategory(rawValue: experienceTypeRaw) ?? .work
    }

    func dateRangeText() -> String {
        let startText = startDate.map { Employment.displayDateFormatter.string(from: $0) }
        let endText = endDate.map { Employment.displayDateFormatter.string(from: $0) }
        switch (startText, endText) {
        case (nil, nil): return ""
        case (let s?, nil): return "\(s) - Present"
        case (nil, let e?): return e
        case (let s?, let e?): return "\(s) - \(e)"
        }
    }
}
