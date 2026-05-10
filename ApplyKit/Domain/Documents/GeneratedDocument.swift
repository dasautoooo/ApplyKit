//
//  GeneratedDocument.swift
//  ApplyKit
//

import Foundation

struct GeneratedDocument: Identifiable, Codable, Hashable {
    var id: UUID
    var applicationID: UUID
    var kindRaw: String
    var statusRaw: String
    var texPath: String
    var pdfPath: String
    var logPath: String
    var lastBuildLog: String
    var createdAt: Date
    var updatedAt: Date

    init(applicationID: UUID, kind: GeneratedDocumentKind, texPath: String, pdfPath: String = "") {
        self.id = UUID()
        self.applicationID = applicationID
        self.kindRaw = kind.rawValue
        self.statusRaw = GeneratedDocumentStatus.draft.rawValue
        self.texPath = texPath
        self.pdfPath = pdfPath
        self.logPath = ""
        self.lastBuildLog = ""
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
