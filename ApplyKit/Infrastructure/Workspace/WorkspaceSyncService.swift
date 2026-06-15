import Foundation

@MainActor
enum WorkspaceSyncService {
    static func bootstrap(store: AppDataStore, settings: AppSettings) throws {
        if settings.hasConfiguredWorkspace { try activateWorkspace(store: store, settings: settings) }
    }

    static func activateWorkspace(store: AppDataStore, settings: AppSettings, migrateExistingCache: Bool = true) throws {
        let root = try WorkspaceService.workspaceURL(settings: settings)
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }
        let hasFiles = try WorkspaceFiles.hasManagedFiles(at: root)
        try WorkspaceFiles.ensureBaseDirectories(at: root)
        if hasFiles {
            try WorkspaceFiles.ensureWorkspaceFiles(at: root, settings: settings)
            try loadWorkspace(at: root, into: store, settings: settings)
            try migrateExperiencesToEmploymentsIfNeeded(store: store, settings: settings, root: root)
        } else if migrateExistingCache {
            try WorkspaceFiles.ensureWorkspaceFiles(at: root, settings: settings)
            try exportStore(to: root, store: store, settings: settings)
            try migrateExperiencesToEmploymentsIfNeeded(store: store, settings: settings, root: root)
        } else {
            clearStore(store)
            try WorkspaceFiles.ensureWorkspaceFiles(at: root, settings: settings)
            try writeExperienceIndex([], root: root)
            try writeEmploymentIndex([], root: root)
        }
    }

    static func reloadWorkspace(store: AppDataStore, settings: AppSettings) throws {
        let root = try WorkspaceService.workspaceURL(settings: settings)
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }
        try WorkspaceFiles.ensureWorkspaceFiles(at: root, settings: settings)
        try loadWorkspace(at: root, into: store, settings: settings)
        try migrateExperiencesToEmploymentsIfNeeded(store: store, settings: settings, root: root)
    }

    static func persistProfile(_ profile: ResumeProfile, settings: AppSettings) throws {
        guard settings.hasConfiguredWorkspace else { return }
        let root = try WorkspaceService.workspaceURL(settings: settings)
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }
        try WorkspaceFiles.ensureBaseDirectories(at: root)
        try YAMLFileStore.write(WorkspaceFiles.profileDTO(from: profile), to: root.appendingPathComponent(WorkspaceFiles.profileFile))
    }

    static func persistSettings(_ settings: AppSettings) throws {
        guard settings.hasConfiguredWorkspace else { return }
        let root = try WorkspaceService.workspaceURL(settings: settings)
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }
        try WorkspaceFiles.ensureBaseDirectories(at: root)
        try YAMLFileStore.write(WorkspaceFiles.settingsDTO(from: settings), to: root.appendingPathComponent(WorkspaceFiles.settingsFile))
        try YAMLFileStore.write(WorkspaceFiles.manifestDTO(), to: root.appendingPathComponent(WorkspaceFiles.manifestFile))
    }

    static func persistApplication(_ application: JobApplication, documents: [GeneratedDocument], settings: AppSettings) throws {
        let root = try WorkspaceService.workspaceURL(settings: settings)
        try writeApplicationFiles(application, documents: documents, root: root)
    }

    /// File-writing core of `persistApplication`, callable off the main actor. `root` must be
    /// pre-resolved on the main actor via `WorkspaceService.workspaceURL(settings:)`. Used by the
    /// editor's debounced autosave to keep disk I/O off the main thread.
    nonisolated static func writeApplicationFiles(_ application: JobApplication, documents: [GeneratedDocument], root: URL) throws {
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }
        try WorkspaceFiles.ensureBaseDirectories(at: root)
        let appFolder = try WorkspaceFiles.fileURLForApplication(application, in: root)
        for dir in [appFolder,
            appFolder.appendingPathComponent(WorkspaceFiles.resumeDirectory, isDirectory: true),
            appFolder.appendingPathComponent(WorkspaceFiles.coverLetterDirectory, isDirectory: true),
            appFolder.appendingPathComponent(WorkspaceFiles.promptsDirectory, isDirectory: true),
            appFolder.appendingPathComponent(WorkspaceFiles.aiResponsesDirectory, isDirectory: true)] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try application.jobDescription.write(to: appFolder.appendingPathComponent(WorkspaceFiles.jobDescriptionFile), atomically: true, encoding: .utf8)
        try application.notes.write(to: appFolder.appendingPathComponent(WorkspaceFiles.notesFile), atomically: true, encoding: .utf8)
        try application.jdAnalysisText.write(to: appFolder.appendingPathComponent(WorkspaceFiles.jdAnalysisFile), atomically: true, encoding: .utf8)
        if !application.curatedSuggestionsData.isEmpty {
            try application.curatedSuggestionsData.write(to: appFolder.appendingPathComponent(WorkspaceFiles.curatedSuggestionsFile), atomically: true, encoding: .utf8)
        }
        try YAMLFileStore.write(WorkspaceFiles.applicationDTO(from: application, documents: documents, appFolder: appFolder), to: appFolder.appendingPathComponent(WorkspaceFiles.applicationFile))
        try YAMLFileStore.write(WorkspaceFiles.manifestDTO(), to: root.appendingPathComponent(WorkspaceFiles.manifestFile))
    }

    static func persistExperience(_ experience: ExperienceBullet, allExperiences: [ExperienceBullet], settings: AppSettings) throws {
        let root = try WorkspaceService.workspaceURL(settings: settings)
        try writeExperienceFiles(experience, allExperiences: allExperiences, root: root)
    }

    /// File-writing core of `persistExperience`, callable off the main actor (see `writeApplicationFiles`).
    nonisolated static func writeExperienceFiles(_ experience: ExperienceBullet, allExperiences: [ExperienceBullet], root: URL) throws {
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }
        try WorkspaceFiles.ensureBaseDirectories(at: root)
        let desiredURL = try WorkspaceFiles.fileURLForExperience(experience, in: root)
        let existingURL = try WorkspaceFiles.findExperienceFile(id: experience.id, in: root)
        if let existing = existingURL, existing.standardizedFileURL.path != desiredURL.standardizedFileURL.path {
            if FileManager.default.fileExists(atPath: existing.path) { try? FileManager.default.removeItem(at: existing) }
        }
        try YAMLFileStore.write(WorkspaceFiles.experienceDTO(from: experience), to: desiredURL)
        try writeExperienceIndex(allExperiences, root: root)
    }

    static func persistEmployment(_ employment: Employment, allEmployments: [Employment], settings: AppSettings) throws {
        let root = try WorkspaceService.workspaceURL(settings: settings)
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }
        try WorkspaceFiles.ensureWorkspaceFiles(at: root, settings: settings)
        let desiredURL = try WorkspaceFiles.fileURLForEmployment(employment, in: root)
        let existingURL = try WorkspaceFiles.findEmploymentFile(id: employment.id, in: root)
        if let existing = existingURL, existing.standardizedFileURL.path != desiredURL.standardizedFileURL.path {
            if FileManager.default.fileExists(atPath: existing.path) { try? FileManager.default.removeItem(at: existing) }
        }
        try YAMLFileStore.write(WorkspaceFiles.employmentDTO(from: employment), to: desiredURL)
        try writeEmploymentIndex(allEmployments, root: root)
    }

    static func deleteEmploymentFile(_ employment: Employment, remainingEmployments: [Employment], settings: AppSettings?) {
        guard let settings, settings.hasConfiguredWorkspace, let root = try? WorkspaceService.workspaceURL(settings: settings) else { return }
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }
        if let url = try? WorkspaceFiles.findEmploymentFile(id: employment.id, in: root) { try? FileManager.default.removeItem(at: url) }
        try? writeEmploymentIndex(remainingEmployments, root: root)
    }

    static func persistPromptTemplate(_ template: PromptTemplate, settings: AppSettings) throws {
        let root = try WorkspaceService.workspaceURL(settings: settings)
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }
        try WorkspaceFiles.ensureWorkspaceFiles(at: root, settings: settings)
        try YAMLFileStore.write(WorkspaceFiles.promptDTO(from: template), to: try WorkspaceFiles.fileURLForPromptTemplate(template, in: root))
    }

    @discardableResult
    static func persistGeneratedDocument(_ document: GeneratedDocument, application: JobApplication, allDocuments: [GeneratedDocument], settings: AppSettings) throws -> GeneratedDocument {
        let root = try WorkspaceService.workspaceURL(settings: settings)
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }
        try WorkspaceFiles.ensureWorkspaceFiles(at: root, settings: settings)
        let appFolder = try WorkspaceFiles.fileURLForApplication(application, in: root)
        let kindFolder = document.kindRaw == GeneratedDocumentKind.resume.rawValue ? WorkspaceFiles.resumeDirectory : WorkspaceFiles.coverLetterDirectory
        let manifestFolder = appFolder.appendingPathComponent(kindFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: manifestFolder, withIntermediateDirectories: true)
        var updated = document
        if !document.lastBuildLog.trimmed.isEmpty {
            let logURL = manifestFolder.appendingPathComponent("build.log")
            try document.lastBuildLog.write(to: logURL, atomically: true, encoding: .utf8)
            updated.logPath = logURL.path
        }
        try YAMLFileStore.write(WorkspaceFiles.documentManifestDTO(from: updated, application: application, manifestFolder: manifestFolder), to: manifestFolder.appendingPathComponent(WorkspaceFiles.manifestYAML))
        try persistApplication(application, documents: allDocuments, settings: settings)
        return updated
    }

    static func deleteGeneratedDocumentFiles(kind: GeneratedDocumentKind, application: JobApplication, settings: AppSettings) throws {
        let root = try WorkspaceService.workspaceURL(settings: settings)
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }
        guard let appFolder = try? WorkspaceFiles.findApplicationFolder(id: application.id, in: root) else { return }
        let kindFolder = kind == .resume ? WorkspaceFiles.resumeDirectory : WorkspaceFiles.coverLetterDirectory
        let folder = appFolder.appendingPathComponent(kindFolder, isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    static func persistAIRun(_ run: AIRun, application: JobApplication, documents: [GeneratedDocument], settings: AppSettings) throws {
        let root = try WorkspaceService.workspaceURL(settings: settings)
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }
        let appFolder = try WorkspaceFiles.fileURLForApplication(application, in: root)
        let metadataURL = URL(fileURLWithPath: run.responsePath).deletingPathExtension().appendingPathExtension("yml")
        try YAMLFileStore.write(WorkspaceFiles.aiRunDTO(from: run, applicationFolder: appFolder), to: metadataURL)
        try persistApplication(application, documents: documents, settings: settings)
    }

    static func deleteApplicationFiles(_ application: JobApplication, settings: AppSettings?) {
        guard let settings, settings.hasConfiguredWorkspace, let root = try? WorkspaceService.workspaceURL(settings: settings) else { return }
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }
        if let folder = try? WorkspaceFiles.findApplicationFolder(id: application.id, in: root),
           FileManager.default.fileExists(atPath: folder.path) { try? FileManager.default.removeItem(at: folder) }
    }

    static func deleteExperienceFile(_ experience: ExperienceBullet, remainingExperiences: [ExperienceBullet], settings: AppSettings?) {
        guard let settings, settings.hasConfiguredWorkspace, let root = try? WorkspaceService.workspaceURL(settings: settings) else { return }
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }
        if let url = try? WorkspaceFiles.findExperienceFile(id: experience.id, in: root) { try? FileManager.default.removeItem(at: url) }
        try? writeExperienceIndex(remainingExperiences, root: root)
    }

    static func deletePromptTemplateFile(_ template: PromptTemplate, settings: AppSettings?) {
        guard let settings, settings.hasConfiguredWorkspace, let root = try? WorkspaceService.workspaceURL(settings: settings) else { return }
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }
        if let url = try? WorkspaceFiles.findPromptTemplateFile(id: template.id, in: root) { try? FileManager.default.removeItem(at: url) }
    }

    static func resetAllData(store: AppDataStore, settings: AppSettings) throws {
        if settings.hasConfiguredWorkspace, let root = try? WorkspaceService.workspaceURL(settings: settings) {
            let didStart = root.startAccessingSecurityScopedResource()
            defer { if didStart { root.stopAccessingSecurityScopedResource() } }
            try deleteManagedWorkspaceFiles(at: root)
        }
        clearStore(store)
        settings.workspacePath = ""; settings.workspaceBookmark = nil; settings.codexCLIPath = ""
        settings.latexBuildCommand = "latexmk -pdf -interaction=nonstopmode -synctex=1"
        settings.externalEditorPath = ""; settings.resumeTemplatePath = ""; settings.resumeTemplateBookmark = nil
        settings.coverLetterTemplatePath = ""; settings.coverLetterTemplateBookmark = nil
    }

    static func loadActivityHistory(settings: AppSettings) -> [ActivityRecord] {
        guard settings.hasConfiguredWorkspace, let root = try? WorkspaceService.workspaceURL(settings: settings) else { return [] }
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }
        guard let dto = try? YAMLFileStore.read(ActivityLogDTO.self, from: root.appendingPathComponent(WorkspaceFiles.activityLogFile)) else { return [] }
        return dto.entries.compactMap { entry in
            guard let id = UUID(uuidString: entry.id) else { return nil }
            return ActivityRecord(id: id, timestamp: WorkspaceDateCodec.date(from: entry.timestamp) ?? Date(), message: entry.message, succeeded: entry.succeeded)
        }
    }

    static func appendActivityRecord(_ record: ActivityRecord, settings: AppSettings) {
        guard settings.hasConfiguredWorkspace, let root = try? WorkspaceService.workspaceURL(settings: settings) else { return }
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }
        let url = root.appendingPathComponent(WorkspaceFiles.activityLogFile)
        var existing = (try? YAMLFileStore.read(ActivityLogDTO.self, from: url))?.entries ?? []
        existing.insert(ActivityRecordDTO(id: record.id.uuidString, timestamp: WorkspaceDateCodec.string(from: record.timestamp), message: record.message, succeeded: record.succeeded), at: 0)
        if existing.count > 200 { existing = Array(existing.prefix(200)) }
        try? YAMLFileStore.write(ActivityLogDTO(updatedAt: WorkspaceDateCodec.string(from: Date()) ?? "", entries: existing), to: url)
    }

    static func clearActivityHistory(settings: AppSettings) {
        guard settings.hasConfiguredWorkspace, let root = try? WorkspaceService.workspaceURL(settings: settings) else { return }
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }
        let url = root.appendingPathComponent(WorkspaceFiles.activityLogFile)
        try? YAMLFileStore.write(
            ActivityLogDTO(updatedAt: WorkspaceDateCodec.string(from: Date()) ?? "", entries: []),
            to: url
        )
    }

    // MARK: - Private

    private static func loadWorkspace(at root: URL, into store: AppDataStore, settings: AppSettings) throws {
        let settingsURL = root.appendingPathComponent(WorkspaceFiles.settingsFile)
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            WorkspaceFiles.apply(try YAMLFileStore.read(WorkspaceSettingsDTO.self, from: settingsURL), to: settings)
        }
        clearStore(store)
        for url in try WorkspaceFiles.yamlFiles(under: root.appendingPathComponent(WorkspaceFiles.promptTemplatesDirectory, isDirectory: true)) {
            store.promptTemplates.append(WorkspaceFiles.makePromptTemplate(from: try YAMLFileStore.read(PromptTemplateFileDTO.self, from: url)))
        }
        let experienceRoot = root.appendingPathComponent(WorkspaceFiles.experienceBankDirectory, isDirectory: true)
        let employmentRoot = experienceRoot.appendingPathComponent(WorkspaceFiles.employmentsDirectory, isDirectory: true)
        for url in try WorkspaceFiles.yamlFiles(under: employmentRoot) where url.lastPathComponent != WorkspaceFiles.employmentIndexFile {
            store.employments.append(WorkspaceFiles.makeEmployment(from: try YAMLFileStore.read(EmploymentFileDTO.self, from: url)))
        }
        for url in try WorkspaceFiles.yamlFiles(under: experienceRoot) where url.lastPathComponent != WorkspaceFiles.experienceIndexFile && !WorkspaceFiles.isEmploymentURL(url) {
            store.experiences.append(WorkspaceFiles.makeExperience(from: try YAMLFileStore.read(ExperienceFileDTO.self, from: url)))
        }
        let applicationRoot = root.appendingPathComponent(WorkspaceFiles.applicationsDirectory, isDirectory: true)
        let appFiles = try WorkspaceFiles.yamlFiles(under: applicationRoot).filter { $0.lastPathComponent == WorkspaceFiles.applicationFile }
        for url in appFiles {
            store.applications.append(WorkspaceFiles.makeApplication(from: try YAMLFileStore.read(ApplicationFileDTO.self, from: url), appFolder: url.deletingLastPathComponent()))
        }
        for url in appFiles {
            let appFolder = url.deletingLastPathComponent()
            for manifestURL in [appFolder.appendingPathComponent(WorkspaceFiles.resumeDirectory, isDirectory: true).appendingPathComponent(WorkspaceFiles.manifestYAML),
                                appFolder.appendingPathComponent(WorkspaceFiles.coverLetterDirectory, isDirectory: true).appendingPathComponent(WorkspaceFiles.manifestYAML)] where FileManager.default.fileExists(atPath: manifestURL.path) {
                let dto = try YAMLFileStore.read(GeneratedDocumentManifestDTO.self, from: manifestURL)
                let manifestFolder = manifestURL.deletingLastPathComponent()
                let buildLog = dto.buildLogPath.flatMap { try? String(contentsOf: WorkspaceFiles.resolve($0, relativeTo: manifestFolder), encoding: .utf8) } ?? ""
                if let doc = WorkspaceFiles.makeDocument(from: dto, applicationFolder: appFolder, manifestFolder: manifestFolder, buildLog: buildLog) { store.documents.append(doc) }
            }
            let responsesFolder = appFolder.appendingPathComponent(WorkspaceFiles.aiResponsesDirectory, isDirectory: true)
            for metadataURL in try WorkspaceFiles.yamlFiles(under: responsesFolder) {
                if let run = WorkspaceFiles.makeAIRun(from: try YAMLFileStore.read(AIRunFileDTO.self, from: metadataURL), applicationFolder: appFolder) { store.aiRuns.append(run) }
            }
        }
        let profileURL = root.appendingPathComponent(WorkspaceFiles.profileFile)
        if FileManager.default.fileExists(atPath: profileURL.path) {
            store.profile = WorkspaceFiles.makeProfile(from: try YAMLFileStore.read(ResumeProfileDTO.self, from: profileURL))
        }
        sortStore(store)
        try writeExperienceIndex(store.experiences, root: root)
        try writeEmploymentIndex(store.employments, root: root)
    }

    private static func exportStore(to root: URL, store: AppDataStore, settings: AppSettings) throws {
        try WorkspaceFiles.ensureWorkspaceFiles(at: root, settings: settings)
        try YAMLFileStore.write(WorkspaceFiles.settingsDTO(from: settings), to: root.appendingPathComponent(WorkspaceFiles.settingsFile))
        try YAMLFileStore.write(WorkspaceFiles.manifestDTO(), to: root.appendingPathComponent(WorkspaceFiles.manifestFile))
        try YAMLFileStore.write(WorkspaceFiles.profileDTO(from: store.profile), to: root.appendingPathComponent(WorkspaceFiles.profileFile))
        for app in store.applications {
            let appDocs = store.documents.filter { $0.applicationID == app.id }
            try persistApplication(app, documents: appDocs, settings: settings)
            for doc in appDocs { try persistGeneratedDocument(doc, application: app, allDocuments: appDocs, settings: settings) }
        }
        for emp in store.employments { try persistEmployment(emp, allEmployments: store.employments, settings: settings) }
        try writeEmploymentIndex(store.employments, root: root)
        for exp in store.experiences { try persistExperience(exp, allExperiences: store.experiences, settings: settings) }
        try writeExperienceIndex(store.experiences, root: root)
        for template in store.promptTemplates { try persistPromptTemplate(template, settings: settings) }
        for run in store.aiRuns {
            guard let app = store.applications.first(where: { $0.id == run.applicationID }) else { continue }
            try persistAIRun(run, application: app, documents: store.documents.filter { $0.applicationID == app.id }, settings: settings)
        }
    }

    nonisolated private static func writeExperienceIndex(_ experiences: [ExperienceBullet], root: URL) throws {
        let entries = try experiences.sorted { $0.displayTitle < $1.displayTitle }.map { exp in
            ExperienceBankIndexEntryDTO(id: exp.id.uuidString, title: exp.displayTitle, company: exp.company,
                category: exp.roleCategoryRaw, path: try WorkspaceFiles.relativePath(from: root, to: WorkspaceFiles.fileURLForExperience(exp, in: root)))
        }
        try YAMLFileStore.write(ExperienceBankIndexDTO(updatedAt: WorkspaceDateCodec.string(from: Date()) ?? "", entries: entries),
            to: root.appendingPathComponent(WorkspaceFiles.experienceBankDirectory, isDirectory: true).appendingPathComponent(WorkspaceFiles.experienceIndexFile))
    }

    private static func writeEmploymentIndex(_ employments: [Employment], root: URL) throws {
        let sorted = employments.sorted { $0.displayOrder != $1.displayOrder ? $0.displayOrder < $1.displayOrder : $0.companyName < $1.companyName }
        let entries = try sorted.map { emp in
            EmploymentBankIndexEntryDTO(id: emp.id.uuidString, companyName: emp.companyName, role: emp.role,
                dateRange: emp.dateRangeText(), path: try WorkspaceFiles.relativePath(from: root, to: WorkspaceFiles.fileURLForEmployment(emp, in: root)))
        }
        try YAMLFileStore.write(EmploymentBankIndexDTO(updatedAt: WorkspaceDateCodec.string(from: Date()) ?? "", entries: entries),
            to: root.appendingPathComponent(WorkspaceFiles.experienceBankDirectory, isDirectory: true).appendingPathComponent(WorkspaceFiles.employmentsDirectory, isDirectory: true).appendingPathComponent(WorkspaceFiles.employmentIndexFile))
    }

    private static func migrateExperiencesToEmploymentsIfNeeded(store: AppDataStore, settings: AppSettings, root: URL) throws {
        var employments = store.employments
        var experiences = store.experiences
        let unlinked = experiences.filter { $0.employmentID == nil && (!$0.company.trimmed.isEmpty || !$0.role.trimmed.isEmpty) }
        guard !unlinked.isEmpty else { return }
        func key(type: String, company: String, role: String) -> String { [type.trimmed, company.trimmed, role.trimmed].joined(separator: "|").lowercased() }
        var byKey: [String: Employment] = [:]
        for emp in employments { byKey[key(type: emp.experienceTypeRaw, company: emp.companyName, role: emp.role)] = emp }
        for i in 0..<experiences.count {
            guard experiences[i].employmentID == nil,
                  !experiences[i].company.trimmed.isEmpty || !experiences[i].role.trimmed.isEmpty else { continue }
            let bullet = experiences[i]
            let bKey = key(type: bullet.experienceType, company: bullet.company, role: bullet.role)
            if let existing = byKey[bKey] {
                experiences[i].employmentID = existing.id
                try persistExperience(experiences[i], allExperiences: experiences, settings: settings)
                continue
            }
            var emp = Employment(companyName: bullet.company, role: bullet.role, location: "", startDate: nil, endDate: nil,
                displayOrder: employments.count + (byKey.count - employments.count), experienceType: ExperienceCategory(rawValue: bullet.experienceType) ?? .work, referenceURL: "", notes: "")
            emp.createdAt = bullet.createdAt
            employments.append(emp)
            byKey[bKey] = emp
            experiences[i].employmentID = emp.id
            try persistEmployment(emp, allEmployments: employments, settings: settings)
            try persistExperience(experiences[i], allExperiences: experiences, settings: settings)
        }
        store.employments = employments
        store.experiences = experiences
    }

    private static func clearStore(_ store: AppDataStore) {
        store.applications = []; store.documents = []; store.aiRuns = []
        store.experiences = []; store.employments = []; store.promptTemplates = []
        store.profile = ResumeProfile()
    }

    private static func sortStore(_ store: AppDataStore) {
        store.applications.sort { $0.dateSaved > $1.dateSaved }
        store.experiences.sort {
            $0.company != $1.company ? $0.company < $1.company : $0.projectName < $1.projectName
        }
        store.employments.sort {
            $0.displayOrder != $1.displayOrder ? $0.displayOrder < $1.displayOrder : $0.companyName < $1.companyName
        }
        store.documents.sort { $0.createdAt > $1.createdAt }
        store.promptTemplates.sort { $0.name < $1.name }
        store.aiRuns.sort { $0.createdAt > $1.createdAt }
    }

    private static func deleteManagedWorkspaceFiles(at root: URL) throws {
        for url in [root.appendingPathComponent(WorkspaceFiles.manifestFile),
                    root.appendingPathComponent(WorkspaceFiles.settingsFile),
                    root.appendingPathComponent(WorkspaceFiles.profileFile),
                    root.appendingPathComponent(WorkspaceFiles.applicationsDirectory, isDirectory: true),
                    root.appendingPathComponent(WorkspaceFiles.experienceBankDirectory, isDirectory: true),
                    root.appendingPathComponent(WorkspaceFiles.promptTemplatesDirectory, isDirectory: true)] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
