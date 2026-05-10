//
//  ApplicationEditorJDAndPersistence.swift
//  ApplyKit
//

import AppKit
import SwiftUI

extension ApplicationEditorView {
    var jobDescriptionSection: some View {
        DetailPanel("Job Description") {
            TextEditor(text: $application.jobDescription)
                .font(.body.monospaced())
                .frame(minHeight: 220)
        }
    }

    var jdAnalysisSection: some View {
        DetailPanel("JD Analysis") {
            Button {
                Task { await analyzeJD() }
            } label: {
                Label(
                    isAnalyzingJD ? "Analyzing…" : (application.jdAnalysisText.trimmed.isEmpty ? "Analyze" : "Re-analyze"),
                    systemImage: "brain"
                )
            }
            .disabled(activityMonitor.state == .running || application.jobDescription.trimmed.isEmpty || aiBackendPath == nil)
            .help(aiBackendPath == nil
                ? "Configure an AI CLI in Settings → Tools"
                : application.jobDescription.trimmed.isEmpty
                    ? "Paste a job description first"
                    : "Analyze the job description with AI")
        } content: {
            if !application.jdAnalysisText.trimmed.isEmpty {
                JDAnalysisView(text: application.jdAnalysisText)
            }
        }
    }

    func analyzeJD() async {
        guard aiBackendPath != nil else { return }
        await MainActor.run {
            isAnalyzingJD = true
            activityMonitor.start("Analyzing job description…")
        }
        do {
            let prompt = PromptBuilder.jdAnalysisPrompt(
                application: application,
                allExperiences: experiences,
                employments: employments
            )
            let result = try await runAI(prompt: prompt)
            await MainActor.run {
                application.jdAnalysisText = result
                persistApplicationChanges()
                isAnalyzingJD = false
                activityMonitor.succeed("JD analysis complete.")
            }
        } catch {
            await MainActor.run {
                isAnalyzingJD = false
                activityMonitor.fail(error.localizedDescription)
            }
        }
    }

    var notesSection: some View {
        DetailPanel("Notes") {
            TextEditor(text: $application.notes)
                .frame(minHeight: 120)
        }
    }

    var aiBackendPath: (path: String, usesClaude: Bool)? {
        guard let s = settings else { return nil }
        let preferClaude = s.preferredAIBackendRaw != "Codex"
        let claude = s.claudeCLIPath.trimmed.isEmpty ? nil : (s.claudeCLIPath, true)
        let codex  = s.codexCLIPath.trimmed.isEmpty  ? nil : (s.codexCLIPath,  false)
        return preferClaude ? (claude ?? codex) : (codex ?? claude)
    }

    func runAI(prompt: String) async throws -> String {
        guard let backend = aiBackendPath else { throw WorkflowError.missingClaudeCLIPath }
        if backend.usesClaude {
            return try await ClaudeService.run(prompt: prompt, claudePath: backend.path, workingDirectory: nil)
        } else {
            let result = try await CodexService.run(prompt: prompt, codexPath: backend.path, workingDirectory: nil)
            return result.standardOutput.trimmed
        }
    }

    var applicationPersistenceFingerprint: String {
        [
            application.id.uuidString,
            application.companyName,
            application.jobTitle,
            application.jobURL,
            application.location,
            application.workModeRaw,
            application.employmentTypeRaw,
            application.sourceRaw,
            application.statusRaw,
            application.priorityRaw,
            WorkspaceDateCodec.string(from: application.dateSaved) ?? "",
            WorkspaceDateCodec.string(from: application.dateApplied) ?? "",
            WorkspaceDateCodec.string(from: application.deadline) ?? "",
            application.referralContact,
            application.recruiterContact,
            application.nextAction,
            application.notes,
            application.jobDescription,
            String(application.coverLetterNeeded),
            application.selectedExperienceIDsText,
            application.selectedProjectIDsText,
            application.selectedVariantIDsText,
            WorkspaceDateCodec.string(from: application.archivedAt) ?? ""
        ].joined(separator: "\u{1F}")
    }

    func persistApplicationChanges() {
        persistApplicationChanges(application)
    }

    func persistApplicationChanges(_ targetApplication: JobApplication) {
        var target = targetApplication
        target.updatedAt = Date()
        guard let settings else { return }
        do {
            let docs = store.documents.filter { $0.applicationID == target.id }
            try WorkspaceSyncService.persistApplication(target, documents: docs, settings: settings)
            if let idx = store.applications.firstIndex(where: { $0.id == target.id }) {
                store.applications[idx] = target
            }
            if target.id == application.id {
                application = target
            }
        } catch {
            activityMonitor.fail(error.localizedDescription)
        }
    }

    func persistExperienceChanges(_ experience: ExperienceBullet) {
        var updated = experience
        updated.updatedAt = Date()
        guard let settings else { return }
        do {
            try WorkspaceSyncService.persistExperience(updated, allExperiences: store.experiences, settings: settings)
            if let idx = store.experiences.firstIndex(where: { $0.id == updated.id }) {
                store.experiences[idx] = updated
            }
        } catch {
            activityMonitor.fail(error.localizedDescription)
        }
    }

    func suggestExperiences() async {
        guard aiBackendPath != nil else { return }
        await MainActor.run {
            isSuggestingExperiences = true
            activityMonitor.start("Asking AI to suggest experiences…")
        }
        do {
            let prompt = PromptBuilder.experienceRecommendationPrompt(
                application: application,
                allExperiences: experiences
            )
            let response = try await runAI(prompt: prompt)
            let validIDs = Set(experiences.map(\.id))
            let recommended = PromptBuilder.parseRecommendedIDs(from: response, validIDs: validIDs)
            await MainActor.run {
                for exp in experiences { application.setExperience(exp.id, selected: false) }
                for id in recommended { application.setExperience(id, selected: true) }
                persistApplicationChanges()
                isSuggestingExperiences = false
                if recommended.isEmpty {
                    activityMonitor.fail("AI didn't return recognisable IDs. Try adding a job description first.")
                } else {
                    activityMonitor.succeed("Suggested \(recommended.count) experience\(recommended.count == 1 ? "" : "s").")
                }
            }
        } catch {
            await MainActor.run {
                isSuggestingExperiences = false
                activityMonitor.fail(error.localizedDescription)
            }
        }
    }
}
