import Foundation

enum WorkspaceService {
    static func bookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolveURL(path: String, bookmark: Data?) throws -> URL {
        if let bookmark {
            var isStale = false
            return try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                           relativeTo: nil, bookmarkDataIsStale: &isStale)
        }
        guard !path.trimmed.isEmpty else { throw WorkflowError.invalidPath(path) }
        return URL(fileURLWithPath: path)
    }

    static func workspaceURL(settings: AppSettings) throws -> URL {
        guard settings.workspaceBookmark != nil || !settings.workspacePath.trimmed.isEmpty else {
            throw WorkflowError.missingWorkspace
        }
        return try resolveURL(path: settings.workspacePath, bookmark: settings.workspaceBookmark)
    }

    static func templateURL(kind: GeneratedDocumentKind, settings: AppSettings) throws -> URL {
        let path: String
        let bookmark: Data?
        switch kind {
        case .resume:   path = settings.resumeTemplatePath;     bookmark = settings.resumeTemplateBookmark
        case .coverLetter: path = settings.coverLetterTemplatePath; bookmark = settings.coverLetterTemplateBookmark
        }
        if bookmark != nil || !path.trimmed.isEmpty { return try resolveURL(path: path, bookmark: bookmark) }
        let resource = kind == .resume ? "general_resume" : "cover_letter"
        guard let url = bundledTemplateURL(resource: resource, extension: "tex") else {
            throw WorkflowError.missingBundledTemplate("\(resource).tex")
        }
        return url
    }

    static func ensureApplicationFolder(for application: JobApplication, settings: AppSettings) throws -> URL {
        let workspace = try workspaceURL(settings: settings)
        let didStart = workspace.startAccessingSecurityScopedResource()
        defer { if didStart { workspace.stopAccessingSecurityScopedResource() } }
        try WorkspaceFiles.ensureWorkspaceFiles(at: workspace, settings: settings)
        let root = try WorkspaceFiles.fileURLForApplication(application, in: workspace)
        for folder in [root,
            root.appendingPathComponent(WorkspaceFiles.resumeDirectory, isDirectory: true),
            root.appendingPathComponent(WorkspaceFiles.coverLetterDirectory, isDirectory: true),
            root.appendingPathComponent(WorkspaceFiles.promptsDirectory, isDirectory: true),
            root.appendingPathComponent(WorkspaceFiles.aiResponsesDirectory, isDirectory: true)] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try application.jobDescription.write(to: root.appendingPathComponent(WorkspaceFiles.jobDescriptionFile), atomically: true, encoding: .utf8)
        try application.notes.write(to: root.appendingPathComponent(WorkspaceFiles.notesFile), atomically: true, encoding: .utf8)
        return root
    }

    static func generateDocument(
        kind: GeneratedDocumentKind,
        for application: JobApplication,
        selectedExperiences: [ExperienceBullet],
        selectedProjects: [ExperienceBullet],
        employments: [Employment],
        profile: ResumeProfile,
        settings: AppSettings,
        renderedCoverLetterTex: String? = nil
    ) throws -> GeneratedFileResult {
        let root = try ensureApplicationFolder(for: application, settings: settings)
        let template = try templateURL(kind: kind, settings: settings)
        let outputFolder = root.appendingPathComponent(
            kind == .resume ? WorkspaceFiles.resumeDirectory : WorkspaceFiles.coverLetterDirectory,
            isDirectory: true)
        let baseName = fileBaseName(kind: kind, application: application, name: profile.fullName)
        let texURL = outputFolder.appendingPathComponent("\(baseName).tex")
        let pdfURL = outputFolder.appendingPathComponent("\(baseName).pdf")
        guard !FileManager.default.fileExists(atPath: texURL.path) else {
            throw WorkflowError.fileAlreadyExists(texURL.path)
        }
        var warnings: [String] = []
        if kind == .resume {
            let templateText = try String(contentsOf: template, encoding: .utf8)
            let render = ResumeRenderer.render(
                template: templateText, variantSelections: application.selectedVariantIDs,
                selectedExperiences: selectedExperiences, selectedProjects: selectedProjects, employments: employments,
                roleDescriptionOverrides: application.employmentRoleDescriptions,
                experienceOrder: application.experienceOrder,
                educationBlock: profile.educationBlock,
                skillsBlock: application.effectiveSkillsBlock(default: profile.skillsBlock),
                summary: application.summaryText,
                sectionOrder: application.sectionOrder)
            warnings = render.warnings
            try profile.applying(to: render.rendered).write(to: texURL, atomically: true, encoding: .utf8)
            try copyResumeClassIfAvailable(templateURL: template, outputFolder: outputFolder)
        } else {
            if let renderedCoverLetterTex, !renderedCoverLetterTex.trimmed.isEmpty {
                try profile.applying(to: renderedCoverLetterTex).write(to: texURL, atomically: true, encoding: .utf8)
            } else {
                try FileManager.default.copyItem(at: template, to: texURL)
            }
        }
        return GeneratedFileResult(texURL: texURL, pdfURL: pdfURL, warnings: warnings)
    }

    static func saveAIFiles(application: JobApplication, purpose: PromptPurpose,
                               prompt: String, result: CommandResult, settings: AppSettings) throws -> (promptPath: String, responsePath: String) {
        let root = try ensureApplicationFolder(for: application, settings: settings)
        let ts = fileTimestamp()
        let purposeSlug = slug(from: purpose.rawValue)
        let promptURL = root.appendingPathComponent(WorkspaceFiles.promptsDirectory).appendingPathComponent("\(ts)-\(purposeSlug).md")
        let responseURL = root.appendingPathComponent(WorkspaceFiles.aiResponsesDirectory).appendingPathComponent("\(ts)-\(purposeSlug).txt")
        try prompt.write(to: promptURL, atomically: true, encoding: .utf8)
        try result.combinedOutput.write(to: responseURL, atomically: true, encoding: .utf8)
        return (promptURL.path, responseURL.path)
    }

    static func slug(for application: JobApplication) -> String {
        let raw = [application.companyName, application.jobTitle].map(\.trimmed).filter { !$0.isEmpty }.joined(separator: "_")
        return slug(from: raw.isEmpty ? "Untitled_Application" : raw)
    }

    static func slug(from value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        var output = ""
        var lastWasSeparator = false
        for scalar in value.unicodeScalars {
            if allowed.contains(scalar) { output.append(Character(scalar)); lastWasSeparator = false }
            else if !lastWasSeparator { output.append("_"); lastWasSeparator = true }
        }
        return output.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func fileTimestamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f.string(from: Date())
    }

    private static func fileBaseName(kind: GeneratedDocumentKind, application: JobApplication, name: String) -> String {
        let personSlug = slug(from: name.trimmed.isEmpty ? "Applicant" : name)
        let appSlug = slug(for: application)
        return kind == .resume ? "\(personSlug)_Resume_\(appSlug)" : "\(personSlug)_Cover_Letter_\(appSlug)"
    }

    private static func bundledTemplateURL(resource: String, extension ext: String) -> URL? {
        Bundle.main.url(forResource: resource, withExtension: ext, subdirectory: "Templates")
            ?? Bundle.main.url(forResource: resource, withExtension: ext)
    }

    private static func copyResumeClassIfAvailable(templateURL: URL, outputFolder: URL) throws {
        let sibling = templateURL.deletingLastPathComponent().appendingPathComponent("resume.cls")
        let bundled = bundledTemplateURL(resource: "resume", extension: "cls")
        let destination = outputFolder.appendingPathComponent("resume.cls")
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        if FileManager.default.fileExists(atPath: sibling.path) {
            try FileManager.default.copyItem(at: sibling, to: destination)
        } else if let bundled { try FileManager.default.copyItem(at: bundled, to: destination) }
    }
}
