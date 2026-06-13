import Foundation

enum WorkspaceFiles {
    static let activityLogFile = "activity-log.yml"
    static let manifestFile = "applykit.yml"
    static let settingsFile = "settings.yml"
    static let profileFile = "profile.yml"
    static let applicationsDirectory = "applications"
    static let experienceBankDirectory = "experience-bank"
    static let promptTemplatesDirectory = "prompt-templates"
    static let applicationFile = "application.yml"
    static let jobDescriptionFile = "job-description.md"
    static let notesFile = "notes.md"
    static let jdAnalysisFile = "jd-analysis.md"
    static let curatedSuggestionsFile = "curated-suggestions.json"
    static let manifestYAML = "manifest.yml"
    static let resumeDirectory = "resume"
    static let coverLetterDirectory = "cover-letter"
    static let promptsDirectory = "prompts"
    static let aiResponsesDirectory = "ai-responses"
    static let experienceIndexFile = "index.yml"
    static let employmentsDirectory = "employments"
    static let employmentIndexFile = "index.yml"

    static func manifestDTO() -> WorkspaceManifestDTO {
        WorkspaceManifestDTO(name: "ApplyKit Workspace", schemaVersion: 1,
            managedDirectories: [applicationsDirectory, experienceBankDirectory, promptTemplatesDirectory],
            updatedAt: WorkspaceDateCodec.string(from: Date()) ?? "")
    }

    static func ensureBaseDirectories(at root: URL) throws {
        for folder in [root,
            root.appendingPathComponent(applicationsDirectory, isDirectory: true),
            root.appendingPathComponent(experienceBankDirectory, isDirectory: true),
            root.appendingPathComponent(promptTemplatesDirectory, isDirectory: true)] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    static func ensureWorkspaceFiles(at root: URL, settings: AppSettings) throws {
        try ensureBaseDirectories(at: root)
        let manifestURL = root.appendingPathComponent(manifestFile)
        if !FileManager.default.fileExists(atPath: manifestURL.path) { try YAMLFileStore.write(manifestDTO(), to: manifestURL) }
        let settingsURL = root.appendingPathComponent(settingsFile)
        if !FileManager.default.fileExists(atPath: settingsURL.path) { try YAMLFileStore.write(settingsDTO(from: settings), to: settingsURL) }
    }

    static func hasManagedFiles(at root: URL) throws -> Bool {
        let manager = FileManager.default
        if manager.fileExists(atPath: root.appendingPathComponent(manifestFile).path) { return true }
        if manager.fileExists(atPath: root.appendingPathComponent(settingsFile).path) { return true }
        let appRoot = root.appendingPathComponent(applicationsDirectory, isDirectory: true)
        if try yamlFiles(under: appRoot).contains(where: { $0.lastPathComponent == applicationFile }) { return true }
        let expRoot = root.appendingPathComponent(experienceBankDirectory, isDirectory: true)
        if try yamlFiles(under: expRoot).contains(where: { url in
            isEmploymentURL(url) ? url.lastPathComponent != employmentIndexFile : url.lastPathComponent != experienceIndexFile
        }) { return true }
        return !(try yamlFiles(under: root.appendingPathComponent(promptTemplatesDirectory, isDirectory: true)).isEmpty)
    }

    static func yamlFiles(under root: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true { continue }
            if url.pathExtension == "yml" || url.pathExtension == "yaml" { files.append(url) }
        }
        return files.sorted { $0.path < $1.path }
    }

    static func settingsDTO(from settings: AppSettings) -> WorkspaceSettingsDTO {
        WorkspaceSettingsDTO(codexCLIPath: settings.codexCLIPath, claudeCLIPath: settings.claudeCLIPath,
            preferredAIBackend: settings.preferredAIBackendRaw, latexBuildCommand: settings.latexBuildCommand,
            externalEditorPath: settings.externalEditorPath, resumeTemplatePath: settings.resumeTemplatePath,
            coverLetterTemplatePath: settings.coverLetterTemplatePath, updatedAt: WorkspaceDateCodec.string(from: Date()))
    }

    static func apply(_ dto: WorkspaceSettingsDTO, to settings: AppSettings) {
        settings.codexCLIPath = dto.codexCLIPath; settings.claudeCLIPath = dto.claudeCLIPath ?? ""
        settings.preferredAIBackendRaw = dto.preferredAIBackend ?? "Claude"
        settings.latexBuildCommand = dto.latexBuildCommand; settings.externalEditorPath = dto.externalEditorPath
        settings.resumeTemplatePath = dto.resumeTemplatePath; settings.coverLetterTemplatePath = dto.coverLetterTemplatePath
    }

    // MARK: - Application
    static func applicationDTO(from application: JobApplication, documents: [GeneratedDocument], appFolder: URL) -> ApplicationFileDTO {
        let links = documents.map { doc in
            ApplicationDocumentLinkDTO(kind: doc.kindRaw,
                manifestPath: "\(doc.kindRaw == GeneratedDocumentKind.resume.rawValue ? resumeDirectory : coverLetterDirectory)/\(manifestYAML)",
                texPath: relativePath(from: appFolder, to: URL(fileURLWithPath: doc.texPath)),
                pdfPath: relativePath(from: appFolder, to: URL(fileURLWithPath: doc.pdfPath)),
                status: doc.statusRaw)
        }
        return ApplicationFileDTO(id: application.id.uuidString, companyName: application.companyName, jobTitle: application.jobTitle,
            jobURL: application.jobURL, location: application.location, workMode: application.workModeRaw,
            employmentType: application.employmentTypeRaw, source: application.sourceRaw, status: application.statusRaw, priority: application.priorityRaw,
            dateSaved: WorkspaceDateCodec.string(from: application.dateSaved), dateApplied: WorkspaceDateCodec.string(from: application.dateApplied),
            deadline: WorkspaceDateCodec.string(from: application.deadline), referralContact: application.referralContact,
            recruiterContact: application.recruiterContact, nextAction: application.nextAction, coverLetterNeeded: application.coverLetterNeeded,
            selectedExperienceIDs: application.selectedExperienceIDs.map(\.uuidString).sorted(),
            selectedProjectIDs: application.selectedProjectIDs.map(\.uuidString).sorted(),
            selectedVariantIDs: variantSelectionDTO(from: application),
            selectedRoleDescriptions: roleDescriptionDTO(from: application),
            archivedAt: WorkspaceDateCodec.string(from: application.archivedAt),
            createdAt: WorkspaceDateCodec.string(from: application.createdAt), updatedAt: WorkspaceDateCodec.string(from: application.updatedAt),
            paths: ApplicationPathsDTO(jobDescription: jobDescriptionFile, notes: notesFile, jdAnalysis: jdAnalysisFile),
            documents: links)
    }

    static func makeApplication(from dto: ApplicationFileDTO, appFolder: URL) -> JobApplication {
        var app = JobApplication(companyName: dto.companyName, jobTitle: dto.jobTitle,
            status: ApplicationStatus(rawValue: dto.status) ?? .saved, priority: ApplicationPriority(rawValue: dto.priority) ?? .medium)
        if let id = UUID(uuidString: dto.id) { app.id = id }
        app.jobURL = dto.jobURL; app.location = dto.location; app.workModeRaw = dto.workMode
        app.employmentTypeRaw = dto.employmentType; app.sourceRaw = dto.source
        app.dateSaved = WorkspaceDateCodec.date(from: dto.dateSaved) ?? Date()
        app.dateApplied = WorkspaceDateCodec.date(from: dto.dateApplied); app.deadline = WorkspaceDateCodec.date(from: dto.deadline)
        app.referralContact = dto.referralContact; app.recruiterContact = dto.recruiterContact; app.nextAction = dto.nextAction
        app.coverLetterNeeded = dto.coverLetterNeeded
        app.selectedExperienceIDsText = dto.selectedExperienceIDs.sorted().joined(separator: ",")
        app.selectedProjectIDsText = (dto.selectedProjectIDs ?? []).sorted().joined(separator: ",")
        app.selectedVariantIDsText = JobApplication.encodeVariantSelections(variantSelections(from: dto.selectedVariantIDs))
        app.employmentRoleDescriptionsText = JobApplication.encodeRoleDescriptions(roleDescriptions(from: dto.selectedRoleDescriptions))
        app.archivedAt = WorkspaceDateCodec.date(from: dto.archivedAt)
        app.createdAt = WorkspaceDateCodec.date(from: dto.createdAt) ?? Date()
        app.updatedAt = WorkspaceDateCodec.date(from: dto.updatedAt) ?? Date()
        app.jobDescription = (try? String(contentsOf: resolve(dto.paths.jobDescription, relativeTo: appFolder), encoding: .utf8)) ?? ""
        app.notes = (try? String(contentsOf: resolve(dto.paths.notes, relativeTo: appFolder), encoding: .utf8)) ?? ""
        if let ap = dto.paths.jdAnalysis {
            app.jdAnalysisText = (try? String(contentsOf: resolve(ap, relativeTo: appFolder), encoding: .utf8)) ?? ""
        }
        app.curatedSuggestionsData = (try? String(contentsOf: appFolder.appendingPathComponent(curatedSuggestionsFile), encoding: .utf8)) ?? ""
        return app
    }

    static func variantSelectionDTO(from application: JobApplication) -> [String: String] {
        Dictionary(uniqueKeysWithValues: application.selectedVariantIDs.map { ($0.key.uuidString, $0.value.uuidString) })
    }

    static func variantSelections(from dto: [String: String]?) -> [UUID: UUID] {
        guard let dto else { return [:] }
        return Dictionary(uniqueKeysWithValues: dto.compactMap { key, value in
            guard let eID = UUID(uuidString: key), let vID = UUID(uuidString: value) else { return nil }
            return (eID, vID)
        })
    }

    static func roleDescriptionDTO(from application: JobApplication) -> [String: String] {
        Dictionary(uniqueKeysWithValues: application.employmentRoleDescriptions.map { ($0.key.uuidString, $0.value) })
    }

    static func roleDescriptions(from dto: [String: String]?) -> [UUID: String] {
        guard let dto else { return [:] }
        return Dictionary(uniqueKeysWithValues: dto.compactMap { key, value in
            guard let eID = UUID(uuidString: key) else { return nil }
            return (eID, value)
        })
    }

    // MARK: - Experience
    static func experienceDTO(from experience: ExperienceBullet) -> ExperienceFileDTO {
        ExperienceFileDTO(id: experience.id.uuidString, experienceType: experience.experienceType,
            company: experience.company, role: experience.role, projectName: experience.projectName,
            bulletText: experience.bulletText, variations: experience.variations.map { variationDTO(from: $0) },
            skills: experience.parsedSkills, roleCategory: experience.roleCategoryRaw, impactLevel: experience.impactLevelRaw,
            usableInResume: experience.usableInResume, usableInCoverLetter: experience.usableInCoverLetter,
            referenceURL: experience.referenceURL,
            resumeDisplayName: experience.resumeDisplayName.isEmpty ? nil : experience.resumeDisplayName,
            notes: experience.notes.isEmpty ? nil : experience.notes,
            employmentID: experience.employmentID?.uuidString,
            createdAt: WorkspaceDateCodec.string(from: experience.createdAt), updatedAt: WorkspaceDateCodec.string(from: experience.updatedAt))
    }

    static func makeExperience(from dto: ExperienceFileDTO) -> ExperienceBullet {
        var exp = ExperienceBullet(experienceType: dto.experienceType, company: dto.company, role: dto.role,
            projectName: dto.projectName, bulletText: dto.bulletText,
            variations: dto.variations.compactMap { makeVariation(from: $0) },
            skillsText: dto.skills.joined(separator: ", "),
            roleCategory: RoleCategory(rawValue: dto.roleCategory) ?? .generalSoftware,
            impactLevel: ImpactLevel(rawValue: dto.impactLevel) ?? .medium,
            usableInResume: dto.usableInResume, usableInCoverLetter: dto.usableInCoverLetter,
            referenceURL: dto.referenceURL, employmentID: dto.employmentID.flatMap { UUID(uuidString: $0) })
        if let id = UUID(uuidString: dto.id) { exp.id = id }
        exp.resumeDisplayName = dto.resumeDisplayName ?? ""
        exp.notes = dto.notes ?? ""
        exp.createdAt = WorkspaceDateCodec.date(from: dto.createdAt) ?? Date()
        exp.updatedAt = WorkspaceDateCodec.date(from: dto.updatedAt) ?? Date()
        return exp
    }

    static func variationDTO(from variation: ExperienceVariation) -> ExperienceVariationDTO {
        ExperienceVariationDTO(id: variation.id.uuidString, name: variation.name, bulletText: variation.bulletText,
            notes: variation.notes, createdAt: WorkspaceDateCodec.string(from: variation.createdAt),
            updatedAt: WorkspaceDateCodec.string(from: variation.updatedAt))
    }

    static func makeVariation(from dto: ExperienceVariationDTO) -> ExperienceVariation? {
        guard let id = UUID(uuidString: dto.id) else { return nil }
        return ExperienceVariation(id: id, name: dto.name, bulletText: dto.bulletText, notes: dto.notes,
            createdAt: WorkspaceDateCodec.date(from: dto.createdAt) ?? Date(),
            updatedAt: WorkspaceDateCodec.date(from: dto.updatedAt) ?? Date())
    }

    // MARK: - Employment
    static func employmentDTO(from employment: Employment) -> EmploymentFileDTO {
        EmploymentFileDTO(id: employment.id.uuidString, companyName: employment.companyName, role: employment.role,
            location: employment.location, startDate: WorkspaceDateCodec.string(from: employment.startDate),
            endDate: WorkspaceDateCodec.string(from: employment.endDate), displayOrder: employment.displayOrder,
            experienceType: employment.experienceTypeRaw, referenceURL: employment.referenceURL, notes: employment.notes,
            roleDescription: employment.roleDescription, createdAt: WorkspaceDateCodec.string(from: employment.createdAt),
            updatedAt: WorkspaceDateCodec.string(from: employment.updatedAt))
    }

    static func makeEmployment(from dto: EmploymentFileDTO) -> Employment {
        var emp = Employment(companyName: dto.companyName, role: dto.role, location: dto.location,
            startDate: WorkspaceDateCodec.date(from: dto.startDate), endDate: WorkspaceDateCodec.date(from: dto.endDate),
            displayOrder: dto.displayOrder, experienceType: ExperienceCategory(rawValue: dto.experienceType) ?? .work,
            referenceURL: dto.referenceURL, notes: dto.notes, roleDescription: dto.roleDescription ?? "")
        if let id = UUID(uuidString: dto.id) { emp.id = id }
        emp.createdAt = WorkspaceDateCodec.date(from: dto.createdAt) ?? Date()
        emp.updatedAt = WorkspaceDateCodec.date(from: dto.updatedAt) ?? Date()
        return emp
    }

    // MARK: - Prompt Templates & Documents
    static func promptDTO(from template: PromptTemplate) -> PromptTemplateFileDTO {
        PromptTemplateFileDTO(id: template.id.uuidString, name: template.name, purpose: template.purposeRaw,
            templateText: template.templateText, isDefault: template.isDefault,
            createdAt: WorkspaceDateCodec.string(from: template.createdAt), updatedAt: WorkspaceDateCodec.string(from: template.updatedAt))
    }

    static func makePromptTemplate(from dto: PromptTemplateFileDTO) -> PromptTemplate {
        var t = PromptTemplate(name: dto.name, purpose: PromptPurpose(rawValue: dto.purpose) ?? .analyzeJob,
            templateText: dto.templateText, isDefault: dto.isDefault)
        if let id = UUID(uuidString: dto.id) { t.id = id }
        t.createdAt = WorkspaceDateCodec.date(from: dto.createdAt) ?? Date()
        t.updatedAt = WorkspaceDateCodec.date(from: dto.updatedAt) ?? Date()
        return t
    }

    static func makeDocument(from dto: GeneratedDocumentManifestDTO, applicationFolder: URL, manifestFolder: URL, buildLog: String) -> GeneratedDocument? {
        guard let applicationID = UUID(uuidString: dto.sourceApplicationID) else { return nil }
        var doc = GeneratedDocument(applicationID: applicationID, kind: GeneratedDocumentKind(rawValue: dto.kind) ?? .resume,
            texPath: resolve(dto.texPath, relativeTo: manifestFolder).path,
            pdfPath: resolve(dto.pdfPath, relativeTo: manifestFolder).path)
        if let id = UUID(uuidString: dto.id) { doc.id = id }
        doc.statusRaw = dto.buildStatus
        if let logPath = dto.buildLogPath { doc.logPath = resolve(logPath, relativeTo: manifestFolder).path }
        doc.lastBuildLog = buildLog
        doc.createdAt = WorkspaceDateCodec.date(from: dto.createdAt) ?? Date()
        doc.updatedAt = WorkspaceDateCodec.date(from: dto.updatedAt) ?? Date()
        _ = applicationFolder; return doc
    }

    static func documentManifestDTO(from document: GeneratedDocument, application: JobApplication, manifestFolder: URL) -> GeneratedDocumentManifestDTO {
        let logPath = document.lastBuildLog.trimmed.isEmpty ? nil : relativePath(from: manifestFolder, to: manifestFolder.appendingPathComponent("build.log"))
        return GeneratedDocumentManifestDTO(id: document.id.uuidString, kind: document.kindRaw,
            sourceApplicationID: application.id.uuidString, jobDescriptionPath: "../\(jobDescriptionFile)",
            selectedExperienceIDs: application.selectedExperienceIDs.map(\.uuidString).sorted(),
            selectedProjectIDs: application.selectedProjectIDs.map(\.uuidString).sorted(),
            selectedVariantIDs: variantSelectionDTO(from: application),
            texPath: relativePath(from: manifestFolder, to: URL(fileURLWithPath: document.texPath)),
            pdfPath: relativePath(from: manifestFolder, to: URL(fileURLWithPath: document.pdfPath)),
            buildStatus: document.statusRaw, buildLogPath: logPath,
            createdAt: WorkspaceDateCodec.string(from: document.createdAt), updatedAt: WorkspaceDateCodec.string(from: document.updatedAt))
    }

    static func aiRunDTO(from run: AIRun, applicationFolder: URL) -> AIRunFileDTO {
        AIRunFileDTO(id: run.id.uuidString, applicationID: run.applicationID.uuidString, backend: run.backendRaw, purpose: run.purposeRaw,
            promptPath: relativePath(from: applicationFolder, to: URL(fileURLWithPath: run.promptPath)),
            responsePath: relativePath(from: applicationFolder, to: URL(fileURLWithPath: run.responsePath)),
            errorText: run.errorText, exitCode: run.exitCode, createdAt: WorkspaceDateCodec.string(from: run.createdAt))
    }

    static func makeAIRun(from dto: AIRunFileDTO, applicationFolder: URL) -> AIRun? {
        guard let applicationID = UUID(uuidString: dto.applicationID) else { return nil }
        let promptURL = resolve(dto.promptPath, relativeTo: applicationFolder)
        let responseURL = resolve(dto.responsePath, relativeTo: applicationFolder)
        var run = AIRun(applicationID: applicationID, backend: dto.backend, purpose: PromptPurpose(rawValue: dto.purpose) ?? .analyzeJob,
            promptText: (try? String(contentsOf: promptURL, encoding: .utf8)) ?? "",
            responseText: (try? String(contentsOf: responseURL, encoding: .utf8)) ?? "",
            errorText: dto.errorText, exitCode: dto.exitCode)
        if let id = UUID(uuidString: dto.id) { run.id = id }
        run.promptPath = promptURL.path; run.responsePath = responseURL.path
        run.createdAt = WorkspaceDateCodec.date(from: dto.createdAt) ?? Date()
        return run
    }

    // MARK: - URL helpers
    static func resolve(_ path: String, relativeTo base: URL) -> URL {
        path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path)
    }

    static func relativePath(from base: URL, to url: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        if targetPath == basePath { return "." }
        if targetPath.hasPrefix(basePath + "/") { return String(targetPath.dropFirst(basePath.count + 1)) }
        return targetPath
    }

    static func slug(from value: String, fallback: String) -> String {
        let s = WorkspaceService.slug(from: value)
        return s.trimmed.isEmpty ? fallback : s.lowercased()
    }

    // MARK: - File URL computation
    static func fileURLForApplication(_ application: JobApplication, in root: URL) throws -> URL {
        let raw = [application.companyName, application.jobTitle].map(\.trimmed).filter { !$0.isEmpty }.joined(separator: "_")
        let folderName = slug(from: raw, fallback: application.id.uuidString.lowercased())
        let desired = root.appendingPathComponent(applicationsDirectory, isDirectory: true).appendingPathComponent(folderName, isDirectory: true)
        if let existing = try findApplicationFolder(id: application.id, in: root) {
            if existing.standardizedFileURL.path != desired.standardizedFileURL.path,
               FileManager.default.fileExists(atPath: existing.path),
               !FileManager.default.fileExists(atPath: desired.path) {
                try FileManager.default.moveItem(at: existing, to: desired)
                return desired
            }
            return existing
        }
        return desired
    }

    static func findApplicationFolder(id: UUID, in root: URL) throws -> URL? {
        for file in try yamlFiles(under: root.appendingPathComponent(applicationsDirectory, isDirectory: true))
            where file.lastPathComponent == applicationFile {
            guard let dto = try? YAMLFileStore.read(ApplicationFileDTO.self, from: file),
                  let parsed = UUID(uuidString: dto.id) else { continue }
            if parsed == id { return file.deletingLastPathComponent() }
        }
        return nil
    }

    static func fileURLForExperience(_ experience: ExperienceBullet, in root: URL) throws -> URL {
        root.appendingPathComponent(experienceBankDirectory, isDirectory: true)
            .appendingPathComponent(slug(from: experience.sourceTitle, fallback: "unassigned-source"), isDirectory: true)
            .appendingPathComponent("\(slug(from: experience.displayTitle, fallback: experience.id.uuidString.lowercased())).yml")
    }

    static func findExperienceFile(id: UUID, in root: URL) throws -> URL? {
        for file in try yamlFiles(under: root.appendingPathComponent(experienceBankDirectory, isDirectory: true))
            where file.lastPathComponent != experienceIndexFile && !isEmploymentURL(file) {
            guard let dto = try? YAMLFileStore.read(ExperienceFileDTO.self, from: file),
                  let parsed = UUID(uuidString: dto.id) else { continue }
            if parsed == id { return file }
        }
        return nil
    }

    static func fileURLForEmployment(_ employment: Employment, in root: URL) throws -> URL {
        let cs = slug(from: employment.companyName, fallback: ""); let rs = slug(from: employment.role, fallback: "")
        let combined = (!cs.isEmpty && !rs.isEmpty) ? "\(cs)--\(rs)" : (!cs.isEmpty ? cs : (!rs.isEmpty ? rs : employment.id.uuidString.lowercased()))
        return root.appendingPathComponent(experienceBankDirectory, isDirectory: true)
            .appendingPathComponent(employmentsDirectory, isDirectory: true).appendingPathComponent("\(combined).yml")
    }

    static func findEmploymentFile(id: UUID, in root: URL) throws -> URL? {
        let empRoot = root.appendingPathComponent(experienceBankDirectory, isDirectory: true).appendingPathComponent(employmentsDirectory, isDirectory: true)
        for file in try yamlFiles(under: empRoot) where file.lastPathComponent != employmentIndexFile {
            guard let dto = try? YAMLFileStore.read(EmploymentFileDTO.self, from: file),
                  let parsed = UUID(uuidString: dto.id) else { continue }
            if parsed == id { return file }
        }
        return nil
    }

    static func fileURLForPromptTemplate(_ template: PromptTemplate, in root: URL) throws -> URL {
        if let existing = try findPromptTemplateFile(id: template.id, in: root) { return existing }
        return root.appendingPathComponent(promptTemplatesDirectory, isDirectory: true)
            .appendingPathComponent("\(slug(from: template.name, fallback: template.id.uuidString.lowercased())).yml")
    }

    static func findPromptTemplateFile(id: UUID, in root: URL) throws -> URL? {
        for file in try yamlFiles(under: root.appendingPathComponent(promptTemplatesDirectory, isDirectory: true)) {
            guard let dto = try? YAMLFileStore.read(PromptTemplateFileDTO.self, from: file),
                  let parsed = UUID(uuidString: dto.id) else { continue }
            if parsed == id { return file }
        }
        return nil
    }

    static func isEmploymentURL(_ url: URL) -> Bool {
        url.path.contains("/\(experienceBankDirectory)/\(employmentsDirectory)/")
    }

    // MARK: - Profile
    static func profileDTO(from profile: ResumeProfile) -> ResumeProfileDTO {
        ResumeProfileDTO(fullName: profile.fullName, city: profile.city, phone: profile.phone,
            email: profile.email, linkedin: profile.linkedin, github: profile.github, website: profile.website,
            educationBlock: profile.educationBlock, skillsBlock: profile.skillsBlock,
            updatedAt: WorkspaceDateCodec.string(from: Date()))
    }

    static func makeProfile(from dto: ResumeProfileDTO) -> ResumeProfile {
        ResumeProfile(fullName: dto.fullName, city: dto.city, phone: dto.phone, email: dto.email,
            linkedin: dto.linkedin, github: dto.github, website: dto.website,
            educationBlock: dto.educationBlock, skillsBlock: dto.skillsBlock)
    }
}
