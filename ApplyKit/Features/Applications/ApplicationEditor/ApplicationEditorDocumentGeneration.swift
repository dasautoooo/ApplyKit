//
//  ApplicationEditorDocumentGeneration.swift
//  ApplyKit
//

import AppKit
import SwiftUI

extension ApplicationEditorView {
    func generateDocument(_ kind: GeneratedDocumentKind, replacingExisting: Bool = false) async {
        guard let settings else {
            activityMonitor.fail("Open Settings and choose a workspace before generating files.")
            return
        }

        let selectedIDs = application.selectedExperienceIDs
        let selectedProjectIDs = application.selectedProjectIDs
        let employmentOrderByID: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: employments.map { ($0.id, $0.displayOrder) }
        )
        let selectedExperiences = experiences
            .filter { selectedIDs.contains($0.id) && isWorkLikeSelection($0) }
            .sorted { lhs, rhs in
                let lhsOrder = lhs.employmentID.flatMap { employmentOrderByID[$0] } ?? Int.max
                let rhsOrder = rhs.employmentID.flatMap { employmentOrderByID[$0] } ?? Int.max
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                return lhs.createdAt < rhs.createdAt
            }
        let selectedProjects = experiences
            .filter { selectedProjectIDs.contains($0.id) && isProjectLikeSelection($0) }
            .sorted { lhs, rhs in
                let lhsOrder = lhs.employmentID.flatMap { employmentOrderByID[$0] } ?? Int.max
                let rhsOrder = rhs.employmentID.flatMap { employmentOrderByID[$0] } ?? Int.max
                if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                return lhs.createdAt < rhs.createdAt
            }

        generatingDocumentKind = kind
        activityMonitor.start(activityMessage(for: kind, replacingExisting: replacingExisting))
        do {
            let existingDocuments = documentsForKind(kind)
            let removedIDs = Set(existingDocuments.map(\.id))
            let remainingDocuments = documents.filter { !removedIDs.contains($0.id) }
            if replacingExisting {
                try WorkspaceSyncService.deleteGeneratedDocumentFiles(
                    kind: kind,
                    application: application,
                    settings: settings
                )
                store.documents.removeAll { removedIDs.contains($0.id) }
                try WorkspaceSyncService.persistApplication(
                    application,
                    documents: remainingDocuments,
                    settings: settings
                )
            }

            var aiRun: AIRun?
            let renderedCoverLetterTex: String?
            if kind == .coverLetter {
                let draft = try await generateCoverLetterTex(
                    selectedExperiences: selectedExperiences,
                    selectedProjects: selectedProjects,
                    settings: settings
                )
                renderedCoverLetterTex = draft.tex
                aiRun = draft.run
            } else {
                renderedCoverLetterTex = nil
            }

            let result = try WorkspaceService.generateDocument(
                kind: kind,
                for: application,
                selectedExperiences: selectedExperiences,
                selectedProjects: selectedProjects,
                employments: employments,
                profile: store.profile,
                settings: settings,
                renderedCoverLetterTex: renderedCoverLetterTex
            )
            let document = GeneratedDocument(applicationID: application.id, kind: kind, texPath: result.texURL.path, pdfPath: result.pdfURL.path)
            store.documents.insert(document, at: 0)
            if let run = aiRun {
                store.aiRuns.insert(run, at: 0)
            }
            application.updatedAt = Date()
            let allDocuments = remainingDocuments + [document]
            let persistedDoc = try WorkspaceSyncService.persistGeneratedDocument(
                document,
                application: application,
                allDocuments: allDocuments,
                settings: settings
            )
            if let idx = store.documents.firstIndex(where: { $0.id == persistedDoc.id }) {
                store.documents[idx] = persistedDoc
            }
            if let run = aiRun {
                try WorkspaceSyncService.persistAIRun(
                    run,
                    application: application,
                    documents: allDocuments,
                    settings: settings
                )
            }

            // One-step flow: build the PDF right after rendering, then open it.
            let built = await buildPDF(persistedDoc, allDocuments: allDocuments, settings: settings)
            if let idx = store.documents.firstIndex(where: { $0.id == built.id }) {
                store.documents[idx] = built
            }
            generatingDocumentKind = nil

            let base = replacingExisting ? "\(kind.rawValue) regenerated." : "\(kind.rawValue) generated."
            if built.statusRaw == GeneratedDocumentStatus.built.rawValue {
                FileOpenService.open(path: built.pdfPath)
                let msg = result.warnings.isEmpty ? base : base + " " + result.warnings.joined(separator: " ")
                activityMonitor.succeed(msg)
            } else {
                activityMonitor.fail("\(kind.rawValue) built with errors — see the build log.")
            }
        } catch {
            generatingDocumentKind = nil
            activityMonitor.fail(error.localizedDescription)
        }
    }

    /// Runs the LaTeX build for a freshly-rendered document and persists the resulting
    /// status/log. A build failure is reflected in the returned document (never thrown),
    /// so the `.tex` and build log remain available for debugging.
    private func buildPDF(_ document: GeneratedDocument,
                          allDocuments: [GeneratedDocument],
                          settings: AppSettings) async -> GeneratedDocument {
        var updated = document
        do {
            let result = try await LatexService.build(texPath: document.texPath, command: settings.latexBuildCommand)
            updated.lastBuildLog = result.combinedOutput
            updated.statusRaw = result.succeeded ? GeneratedDocumentStatus.built.rawValue
                                                 : GeneratedDocumentStatus.failed.rawValue
        } catch {
            updated.lastBuildLog = error.localizedDescription
            updated.statusRaw = GeneratedDocumentStatus.failed.rawValue
        }
        updated.updatedAt = Date()
        if let persisted = try? WorkspaceSyncService.persistGeneratedDocument(
            updated, application: application, allDocuments: allDocuments, settings: settings) {
            return persisted
        }
        return updated
    }

    func hasGeneratedDocument(_ kind: GeneratedDocumentKind) -> Bool {
        !documentsForKind(kind).isEmpty
    }

    func documentActionTitle(for kind: GeneratedDocumentKind) -> String {
        if generatingDocumentKind == kind {
            switch kind {
            case .resume: return hasGeneratedDocument(kind) ? "Regenerating Resume…" : "Generating Resume…"
            case .coverLetter: return hasGeneratedDocument(kind) ? "Redrafting Cover Letter…" : "Drafting Cover Letter…"
            }
        }
        switch kind {
        case .resume: return hasGeneratedDocument(kind) ? "Regenerate Resume" : "Generate Resume"
        case .coverLetter: return hasGeneratedDocument(kind) ? "Regenerate Cover Letter" : "Generate Cover Letter"
        }
    }

    private func documentsForKind(_ kind: GeneratedDocumentKind) -> [GeneratedDocument] {
        documents.filter { $0.kindRaw == kind.rawValue }
    }

    private func activityMessage(for kind: GeneratedDocumentKind, replacingExisting: Bool) -> String {
        switch (kind, replacingExisting) {
        case (.resume, true): return "Regenerating resume…"
        case (.resume, false): return "Generating resume…"
        case (.coverLetter, true): return "Redrafting cover letter with AI…"
        case (.coverLetter, false): return "Drafting cover letter with AI…"
        }
    }

    private func generateCoverLetterTex(
        selectedExperiences: [ExperienceBullet],
        selectedProjects: [ExperienceBullet],
        settings: AppSettings
    ) async throws -> (tex: String, run: AIRun) {
        guard let backend = aiBackendPath else { throw WorkflowError.missingClaudeCLIPath }
        let templateURL = try WorkspaceService.templateURL(kind: .coverLetter, settings: settings)
        let templateText = try String(contentsOf: templateURL, encoding: .utf8)
        let prompt = PromptBuilder.coverLetterPrompt(
            application: application,
            selectedExperiences: selectedExperiences,
            selectedProjects: selectedProjects,
            employments: employments
        )
        let backendName = backend.usesClaude ? "Claude" : "Codex"
        let commandResult: CommandResult
        if backend.usesClaude {
            commandResult = try await ClaudeService.runCommand(
                prompt: prompt,
                claudePath: backend.path,
                workingDirectory: nil
            )
        } else {
            commandResult = try await CodexService.run(
                prompt: prompt,
                codexPath: backend.path,
                workingDirectory: nil
            )
        }

        guard !commandResult.standardOutput.trimmed.isEmpty else { throw WorkflowError.emptyAIResponse }
        let draft = try CoverLetterRenderer.parseDraft(from: commandResult.standardOutput)
        let tex = CoverLetterRenderer.render(
            template: templateText,
            draft: draft,
            application: application
        )
        let saved = try WorkspaceService.saveAIFiles(
            application: application,
            purpose: .coverLetterAngle,
            prompt: prompt,
            result: commandResult,
            settings: settings
        )
        var run = AIRun(
            applicationID: application.id,
            backend: backendName,
            purpose: .coverLetterAngle,
            promptText: prompt,
            responseText: commandResult.standardOutput,
            errorText: commandResult.standardError,
            exitCode: Int(commandResult.exitCode)
        )
        run.promptPath = saved.promptPath
        run.responsePath = saved.responsePath
        return (tex, run)
    }
}
