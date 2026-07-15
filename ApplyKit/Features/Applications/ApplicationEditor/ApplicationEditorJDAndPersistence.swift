//
//  ApplicationEditorJDAndPersistence.swift
//  ApplyKit
//

import AppKit
import SwiftUI

extension ApplicationEditorView {
    /// Right-hand "Job Context" inspector: everything about the job itself, kept
    /// alongside the resume-building content so both can be read at once.
    var jobContextInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                jobDescriptionSection
                jdAnalysisSection
                curatedBulletsSection
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    var jobDescriptionSection: some View {
        DetailPanel("Job Description", collapseKey: "applicationEditor.collapsed.jobDescription") {
            TextEditor(text: $application.jobDescription)
                .font(.body.monospaced())
                .frame(minHeight: 220)
        }
    }

    var jdAnalysisSection: some View {
        DetailPanel("JD Analysis", collapseKey: "applicationEditor.collapsed.jdAnalysis") {
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

    var curatedBulletsSection: some View {
        DetailPanel("Experience Gap Suggestions", collapseKey: "applicationEditor.collapsed.gapSuggestions") {
            Button {
                Task { await curateBullets() }
            } label: {
                Label(
                    isCuratingBullets ? "Generating…" : (curatedSuggestions.isEmpty ? "Suggest Bullets" : "Re-generate"),
                    systemImage: "sparkles"
                )
            }
            .disabled(activityMonitor.state == .running || application.jobDescription.trimmed.isEmpty || aiBackendPath == nil)
            .help(aiBackendPath == nil
                ? "Configure an AI CLI in Settings → Tools"
                : application.jobDescription.trimmed.isEmpty
                    ? "Paste a job description first"
                    : "Suggest new experience bullets based on your experience bank")
        } content: {
            if !curatedSuggestions.isEmpty {
                VStack(spacing: 10) {
                    let bulletIDs = Set(experiences.map(\.id))
                    let variantIDsByBullet = Dictionary(uniqueKeysWithValues: experiences.map {
                        ($0.id, Set($0.variations.map(\.id)))
                    })
                    ForEach($curatedSuggestions) { $suggestion in
                        CuratedBulletCard(
                            suggestion: $suggestion,
                            selectedExperienceIDs: application.selectedExperienceIDs,
                            activeVariants: application.selectedVariantIDs,
                            existingBulletIDs: bulletIDs,
                            existingVariantIDsByBullet: variantIDsByBullet,
                            onAddToResume: { addCuratedToResume(id: suggestion.id) },
                            onBankOnly: { addCuratedToBank(id: suggestion.id) }
                        )
                    }
                }
            }
        }
    }

    func curateBullets() async {
        guard aiBackendPath != nil else { return }
        await MainActor.run {
            isCuratingBullets = true
            activityMonitor.start("Generating experience gap suggestions…")
        }
        do {
            let prompt = PromptBuilder.bulletCurationPrompt(
                application: application,
                allExperiences: experiences,
                employments: employments
            )
            let response = try await runAI(prompt: prompt)
            let suggestions = PromptBuilder.parseCuratedSuggestions(from: response, allExperiences: experiences)
            await MainActor.run {
                curatedSuggestions = suggestions
                application.curatedSuggestionsData = encodeCuratedSuggestions(suggestions)
                persistApplicationChanges()
                isCuratingBullets = false
                if suggestions.isEmpty {
                    activityMonitor.fail("Couldn't parse suggestions. Try adding a job description first.")
                } else {
                    activityMonitor.succeed("Generated \(suggestions.count) bullet suggestion\(suggestions.count == 1 ? "" : "s").")
                }
            }
        } catch {
            await MainActor.run {
                isCuratingBullets = false
                activityMonitor.fail(error.localizedDescription)
            }
        }
    }

    func addCuratedToResume(id: UUID) {
        guard let settings,
              let idx = curatedSuggestions.firstIndex(where: { $0.id == id }) else { return }
        let suggestion = curatedSuggestions[idx]
        commitToBank(suggestion: suggestion, settings: settings)
        if let sourceID = suggestion.sourceBulletID,
           let expIdx = store.experiences.firstIndex(where: { $0.id == sourceID }),
           let variant = store.experiences[expIdx].variations.last {
            application.setExperience(sourceID, selected: true)
            application.setVariant(variant.id, for: sourceID)
            curatedSuggestions[idx].addedBulletID = sourceID
            curatedSuggestions[idx].addedVariantID = variant.id
        } else if let newBullet = store.experiences.first(where: { $0.bulletText == suggestion.bulletText }) {
            application.setExperience(newBullet.id, selected: true)
            curatedSuggestions[idx].addedBulletID = newBullet.id
        }
        application.curatedSuggestionsData = encodeCuratedSuggestions(curatedSuggestions)
        persistApplicationChanges()
        activityMonitor.succeed(suggestion.isVariation ? "Wording added and selected for this application." : "Bullet added to resume.")
    }

    func addCuratedToBank(id: UUID) {
        guard let settings,
              let idx = curatedSuggestions.firstIndex(where: { $0.id == id }) else { return }
        let suggestion = curatedSuggestions[idx]
        commitToBank(suggestion: suggestion, settings: settings)
        curatedSuggestions[idx].addedState = .bankOnly
        // Store the bullet ID so we know it's been added even without selecting for resume
        if let sourceID = suggestion.sourceBulletID {
            curatedSuggestions[idx].addedBulletID = sourceID
            if let expIdx = store.experiences.firstIndex(where: { $0.id == sourceID }),
               let variant = store.experiences[expIdx].variations.last {
                curatedSuggestions[idx].addedVariantID = variant.id
            }
        } else if let newBullet = store.experiences.first(where: { $0.bulletText == suggestion.bulletText }) {
            curatedSuggestions[idx].addedBulletID = newBullet.id
        }
        application.curatedSuggestionsData = encodeCuratedSuggestions(curatedSuggestions)
        persistApplicationChanges()
        activityMonitor.succeed(suggestion.isVariation ? "New wording saved to experience bank." : "Bullet saved to experience bank.")
    }

    private func commitToBank(suggestion: CuratedBulletSuggestion, settings: AppSettings) {
        if let sourceID = suggestion.sourceBulletID,
           let idx = store.experiences.firstIndex(where: { $0.id == sourceID }) {
            var existing = store.experiences[idx]
            let variant = ExperienceVariation(
                name: ExperienceVariation.defaultName(existing: existing.variations),
                bulletText: suggestion.bulletText,
                notes: curatedNotes(for: suggestion)
            )
            existing.variations.append(variant)
            store.experiences[idx] = existing
            try? WorkspaceSyncService.persistExperience(existing, allExperiences: store.experiences, settings: settings)
        } else {
            let bullet = ExperienceBullet(bulletText: suggestion.bulletText, notes: curatedNotes(for: suggestion))
            store.experiences.insert(bullet, at: 0)
            try? WorkspaceSyncService.persistExperience(bullet, allExperiences: store.experiences, settings: settings)
        }
    }

    func encodeCuratedSuggestions(_ suggestions: [CuratedBulletSuggestion]) -> String {
        guard let data = try? JSONEncoder().encode(suggestions),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }

    func decodeCuratedSuggestions(_ json: String) -> [CuratedBulletSuggestion] {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let suggestions = try? JSONDecoder().decode([CuratedBulletSuggestion].self, from: data) else { return [] }
        return suggestions
    }

    private func curatedNotes(for suggestion: CuratedBulletSuggestion) -> String {
        var parts: [String] = []
        if !suggestion.relevance.trimmed.isEmpty { parts.append("## Relevance\n\(suggestion.relevance)") }
        if !suggestion.howToLearn.trimmed.isEmpty { parts.append("## How to Learn\n\(suggestion.howToLearn)") }
        if !suggestion.story.trimmed.isEmpty { parts.append("## Your Story\n\(suggestion.story)") }
        return parts.joined(separator: "\n\n")
    }

    var notesSection: some View {
        DetailPanel("Notes", collapseKey: "applicationEditor.collapsed.notes") {
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
            application.employmentRoleDescriptionsText,
            application.hiddenRoleDescriptionIDsText,
            application.experienceOrderText,
            application.sectionOrderText,
            application.skillsBlockText,
            application.summaryText,
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

        // Update the in-memory store synchronously (cheap) so the sidebar and other views
        // reflect the edit immediately...
        let docs = store.documents.filter { $0.applicationID == target.id }
        if let idx = store.applications.firstIndex(where: { $0.id == target.id }) {
            // Archive state is owned by the applications list (archive/restore), not the
            // editor snapshot; preserve it so a stale snapshot can't revert an archive.
            target.archivedAt = store.applications[idx].archivedAt
            store.applications[idx] = target
        }
        if target.id == application.id {
            application = target
        }

        // ...then write the files to disk off the main thread so typing never blocks on I/O.
        guard let root = try? WorkspaceService.workspaceURL(settings: settings) else { return }
        let snapshot = target
        let monitor = activityMonitor
        Task.detached(priority: .utility) {
            do {
                try WorkspaceSyncService.writeApplicationFiles(snapshot, documents: docs, root: root)
            } catch {
                let message = error.localizedDescription
                await MainActor.run { monitor.fail(message) }
            }
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
