//
//  AIRun.swift
//  ApplyKit
//

import Foundation

struct AIRun: Identifiable, Codable, Hashable {
    var id: UUID
    var applicationID: UUID
    var backendRaw: String
    var purposeRaw: String
    var promptPath: String
    var responsePath: String
    var promptText: String
    var responseText: String
    var errorText: String
    var exitCode: Int
    var createdAt: Date

    init(applicationID: UUID, backend: String = "Claude", purpose: PromptPurpose, promptText: String,
         responseText: String = "", errorText: String = "", exitCode: Int = -1) {
        self.id = UUID()
        self.applicationID = applicationID
        self.backendRaw = backend
        self.purposeRaw = purpose.rawValue
        self.promptPath = ""
        self.responsePath = ""
        self.promptText = promptText
        self.responseText = responseText
        self.errorText = errorText
        self.exitCode = exitCode
        self.createdAt = Date()
    }
}
