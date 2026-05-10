//
//  ApplicationEditorComponents.swift
//  ApplyKit
//

import AppKit
import SwiftUI

struct SelectionGroupView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 4) {
                content
            }
        }
    }
}

struct ApplicationExperienceWordingRow: View {
    @Environment(AppActivityMonitor.self) private var activityMonitor
    @Binding var application: JobApplication
    @Binding var experience: ExperienceBullet
    let applications: [JobApplication]
    let settings: AppSettings?
    let onPersistExperience: (ExperienceBullet) -> Void
    let onPersistApplication: (JobApplication) -> Void
    @State private var variantPendingDeletion: ExperienceVariation?
    @State private var showDeleteVariantConfirmation = false
    @State private var isRefining = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(experience.displayTitle)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text([experience.company, experience.role, experience.skillsText].filter { !$0.trimmed.isEmpty }.joined(separator: " - "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(selectedVariant == nil ? "Base" : "Variant")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(selectedVariant == nil ? Color.secondary : Color.blue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background((selectedVariant == nil ? Color.secondary : Color.blue).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack(alignment: .center, spacing: 10) {
                LabeledControl("Wording") {
                    Picker("Wording", selection: selectedVariantBinding) {
                        Text("Base").tag(UUID?.none)
                        ForEach(experience.variations) { variation in
                            Text(variation.displayName).tag(UUID?.some(variation.id))
                        }
                    }
                }

                Button {
                    createVariant(selectingForApplication: true)
                } label: {
                    Label("New Variant", systemImage: "plus")
                }
                .controlSize(.small)

                if rowAIBackendPath != nil {
                    Button {
                        Task { await refineWithAI() }
                    } label: {
                        Label(isRefining ? "Refining…" : "Refine with AI", systemImage: "wand.and.stars")
                    }
                    .controlSize(.small)
                    .disabled(isRefining || activityMonitor.state == .running)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Base bullet")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(experience.bulletText.trimmed.isEmpty ? "No base bullet yet." : experience.bulletText)
                    .font(.body.monospaced())
                    .foregroundStyle(experience.bulletText.trimmed.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            if let variantID = selectedVariant?.id {
                ExperienceVariantEditorCard(
                    variation: variantBinding(for: variantID),
                    usageText: usageText(for: variantID),
                    onDelete: { requestDeleteVariant(variantID) }
                )
            }
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .confirmationDialog(
            "Delete this variant?",
            isPresented: $showDeleteVariantConfirmation,
            presenting: variantPendingDeletion
        ) { variant in
            Button("Delete \(variant.displayName)", role: .destructive) {
                deleteVariant(variant.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { variant in
            Text("This removes \(variant.displayName) from the experience and resets applications using it back to Base.")
        }
    }

    private var selectedVariantID: UUID? {
        guard let id = application.selectedVariantID(for: experience.id),
              experience.variations.contains(where: { $0.id == id }) else {
            return nil
        }
        return id
    }

    private var selectedVariant: ExperienceVariation? {
        guard let selectedVariantID else { return nil }
        return experience.variations.first { $0.id == selectedVariantID }
    }

    private var selectedVariantBinding: Binding<UUID?> {
        Binding(
            get: { selectedVariantID },
            set: { newValue in
                application.setVariant(newValue, for: experience.id)
            }
        )
    }

    private func variantBinding(for variantID: UUID) -> Binding<ExperienceVariation> {
        Binding(
            get: {
                experience.variations.first { $0.id == variantID } ?? ExperienceVariation(name: "Variant")
            },
            set: { newValue in
                var variations = experience.variations
                guard let index = variations.firstIndex(where: { $0.id == variantID }) else { return }
                var updated = newValue
                updated.updatedAt = Date()
                variations[index] = updated
                experience.variations = variations
                onPersistExperience(experience)
            }
        )
    }

    private var rowAIBackendPath: (path: String, usesClaude: Bool)? {
        guard let s = settings else { return nil }
        let preferClaude = s.preferredAIBackendRaw != "Codex"
        let claude = s.claudeCLIPath.trimmed.isEmpty ? nil : (s.claudeCLIPath, true)
        let codex  = s.codexCLIPath.trimmed.isEmpty  ? nil : (s.codexCLIPath,  false)
        return preferClaude ? (claude ?? codex) : (codex ?? claude)
    }

    private func runRowAI(prompt: String) async throws -> String {
        guard let backend = rowAIBackendPath else { throw WorkflowError.missingClaudeCLIPath }
        if backend.usesClaude {
            return try await ClaudeService.run(prompt: prompt, claudePath: backend.path, workingDirectory: nil)
        } else {
            let result = try await CodexService.run(prompt: prompt, codexPath: backend.path, workingDirectory: nil)
            return result.standardOutput.trimmed
        }
    }

    private func refineWithAI() async {
        guard rowAIBackendPath != nil, activityMonitor.state != .running else { return }
        await MainActor.run {
            isRefining = true
            activityMonitor.start("Refining bullet with AI…")
        }
        do {
            let prompt = PromptBuilder.bulletRefinementPrompt(application: application, experience: experience)
            let refined = try await runRowAI(prompt: prompt)
            let text = refined.trimmed
            guard !text.isEmpty else {
                await MainActor.run {
                    isRefining = false
                    activityMonitor.fail("AI returned an empty response.")
                }
                return
            }
            await MainActor.run {
                var variations = experience.variations
                let variant = ExperienceVariation(name: "AI Refined", bulletText: text)
                variations.append(variant)
                experience.variations = variations
                application.setVariant(variant.id, for: experience.id)
                onPersistExperience(experience)
                onPersistApplication(application)
                isRefining = false
                activityMonitor.succeed("Bullet refined — variant added.")
            }
        } catch {
            await MainActor.run {
                isRefining = false
                activityMonitor.fail(error.localizedDescription)
            }
        }
    }

    private func createVariant(selectingForApplication: Bool) {
        var variations = experience.variations
        let variant = ExperienceVariation(
            name: ExperienceVariation.defaultName(existing: variations),
            bulletText: experience.bulletText
        )
        variations.append(variant)
        experience.variations = variations
        if selectingForApplication {
            application.setVariant(variant.id, for: experience.id)
            onPersistApplication(application)
        }
        onPersistExperience(experience)
    }

    private func requestDeleteVariant(_ variantID: UUID) {
        guard let variant = experience.variations.first(where: { $0.id == variantID }) else { return }
        variantPendingDeletion = variant
        showDeleteVariantConfirmation = true
    }

    private func deleteVariant(_ variantID: UUID) {
        var variations = experience.variations
        variations.removeAll { $0.id == variantID }
        experience.variations = variations

        for app in applications where app.selectedVariantID(for: experience.id) == variantID {
            var updated = app
            updated.setVariant(nil, for: experience.id)
            onPersistApplication(updated)
        }

        onPersistExperience(experience)
    }

    private func usageText(for variantID: UUID) -> String {
        let titles = applications
            .filter { $0.selectedVariantID(for: experience.id) == variantID }
            .map(\.displayTitle)
            .sorted()
        guard !titles.isEmpty else {
            return "Not selected by any application yet."
        }
        return "Used by \(titles.joined(separator: ", "))"
    }
}

struct SelectionToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !detail.trimmed.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 3)
    }
}

struct DocumentRow: View {
    @Environment(AppDataStore.self) private var store
    let document: GeneratedDocument
    let application: JobApplication
    let allDocuments: [GeneratedDocument]
    let settings: AppSettings?

    @State private var isBuilding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(document.kindRaw, systemImage: document.kindRaw == GeneratedDocumentKind.resume.rawValue ? "doc.text" : "envelope")
                    .font(.callout.weight(.semibold))
                Text(document.statusRaw)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Capsule())
                Spacer()
                Button {
                    FileOpenService.open(path: document.texPath)
                } label: {
                    Label("Open TeX", systemImage: "doc")
                }
                .controlSize(.small)
                Button {
                    FileOpenService.reveal(path: document.texPath)
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .controlSize(.small)
                Button {
                    build()
                } label: {
                    Label("Build PDF", systemImage: "hammer")
                }
                .disabled(isBuilding || settings == nil)
                .controlSize(.small)
                Button {
                    FileOpenService.open(path: document.pdfPath)
                } label: {
                    Label("Open PDF", systemImage: "doc.richtext")
                }
                .disabled(!FileManager.default.fileExists(atPath: document.pdfPath))
                .controlSize(.small)
            }

            Text(document.texPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if !document.lastBuildLog.trimmed.isEmpty {
                DisclosureGroup("Build log") {
                    Text(document.lastBuildLog)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var statusColor: Color {
        switch document.statusRaw {
        case GeneratedDocumentStatus.built.rawValue: .green
        case GeneratedDocumentStatus.failed.rawValue: .red
        default: .secondary
        }
    }

    private func build() {
        guard let settings else { return }
        isBuilding = true
        Task {
            var updatedDoc = document
            do {
                let result = try await LatexService.build(texPath: document.texPath, command: settings.latexBuildCommand)
                updatedDoc.lastBuildLog = result.combinedOutput
                updatedDoc.statusRaw = result.succeeded ? GeneratedDocumentStatus.built.rawValue : GeneratedDocumentStatus.failed.rawValue
                updatedDoc.updatedAt = Date()
                let persisted = try WorkspaceSyncService.persistGeneratedDocument(
                    updatedDoc,
                    application: application,
                    allDocuments: allDocuments,
                    settings: settings
                )
                if let idx = store.documents.firstIndex(where: { $0.id == persisted.id }) {
                    store.documents[idx] = persisted
                }
            } catch {
                updatedDoc.lastBuildLog = error.localizedDescription
                updatedDoc.statusRaw = GeneratedDocumentStatus.failed.rawValue
                if let persisted = try? WorkspaceSyncService.persistGeneratedDocument(
                    updatedDoc,
                    application: application,
                    allDocuments: allDocuments,
                    settings: settings
                ) {
                    if let idx = store.documents.firstIndex(where: { $0.id == persisted.id }) {
                        store.documents[idx] = persisted
                    }
                }
            }
            isBuilding = false
        }
    }
}

struct JDAnalysisView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(parsedSections.enumerated()), id: \.offset) { index, section in
                VStack(alignment: .leading, spacing: 8) {
                    if !section.title.isEmpty {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                    ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                        switch block {
                        case .paragraph(let s):
                            inlineText(s)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        case .subheader(let s):
                            Text(s)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        case .bullet(let s):
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 10, alignment: .leading)
                                inlineText(s)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                if index < parsedSections.count - 1 {
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func inlineText(_ string: String) -> some View {
        if let attributed = try? AttributedString(markdown: string,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(string)
                .textSelection(.enabled)
        }
    }

    private enum Block {
        case paragraph(String)
        case bullet(String)
        case subheader(String)
    }

    private struct Section {
        var title: String
        var blocks: [Block]
    }

    private var parsedSections: [Section] {
        var sections: [Section] = []
        var current = Section(title: "", blocks: [])
        var pendingLines: [String] = []

        func flushPending(_ lines: [String], into section: inout Section) {
            let joined = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { section.blocks.append(.paragraph(joined)) }
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.hasPrefix("## ") {
                flushPending(pendingLines, into: &current)
                pendingLines = []
                if !current.title.isEmpty || !current.blocks.isEmpty {
                    sections.append(current)
                }
                current = Section(title: String(line.dropFirst(3)), blocks: [])
            } else if line.hasPrefix("###") {
                flushPending(pendingLines, into: &current)
                pendingLines = []
                let heading = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if !heading.isEmpty { current.blocks.append(.subheader(heading)) }
            } else if line == "---" || line == "***" || line == "___" {
                flushPending(pendingLines, into: &current)
                pendingLines = []
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flushPending(pendingLines, into: &current)
                pendingLines = []
                let content = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                current.blocks.append(.bullet(content))
            } else if line.isEmpty {
                flushPending(pendingLines, into: &current)
                pendingLines = []
            } else {
                pendingLines.append(line)
            }
        }
        flushPending(pendingLines, into: &current)
        if !current.title.isEmpty || !current.blocks.isEmpty {
            sections.append(current)
        }
        return sections
    }
}
