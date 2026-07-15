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

struct ExperienceWordingRow<Content: ResumeContentModel & Identifiable>: View where Content.ID == UUID {
    @Environment(AppActivityMonitor.self) private var activityMonitor
    @Binding var content: Content
    @Binding var experience: ExperienceBullet
    let applications: [JobApplication]
    let settings: AppSettings?
    /// Builds the AI refinement prompt for this bullet; nil hides "Refine with AI".
    let refinePrompt: ((ExperienceBullet) -> String)?
    let onPersistExperience: (ExperienceBullet) -> Void
    let onPersistApplication: (JobApplication) -> Void
    let onPersistContent: (Content) -> Void
    var canMoveUp: Bool = false
    var canMoveDown: Bool = false
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}
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

                HStack(spacing: 4) {
                    Button(action: onMoveUp) {
                        Image(systemName: "chevron.up")
                    }
                    .controlSize(.small)
                    .disabled(!canMoveUp)
                    .help("Move up within this section")

                    Button(action: onMoveDown) {
                        Image(systemName: "chevron.down")
                    }
                    .controlSize(.small)
                    .disabled(!canMoveDown)
                    .help("Move down within this section")
                }

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

                if refinePrompt != nil && rowAIBackendPath != nil {
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
        guard let id = content.selectedVariantID(for: experience.id),
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
                var updated = content
                updated.setVariant(newValue, for: experience.id)
                content = updated
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
        guard let refinePrompt, rowAIBackendPath != nil, activityMonitor.state != .running else { return }
        await MainActor.run {
            isRefining = true
            activityMonitor.start("Refining bullet with AI…")
        }
        do {
            let prompt = refinePrompt(experience)
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
                var updated = content
                updated.setVariant(variant.id, for: experience.id)
                content = updated
                onPersistExperience(experience)
                onPersistContent(updated)
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
            var updated = content
            updated.setVariant(variant.id, for: experience.id)
            content = updated
            onPersistContent(updated)
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

        for app in applications where app.id != content.id && app.selectedVariantID(for: experience.id) == variantID {
            var updated = app
            updated.setVariant(nil, for: experience.id)
            onPersistApplication(updated)
        }
        if content.selectedVariantID(for: experience.id) == variantID {
            var updated = content
            updated.setVariant(nil, for: experience.id)
            content = updated
            onPersistContent(updated)
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

struct RoleDescriptionRow<Content: ResumeContentModel>: View {
    @Binding var content: Content
    let employment: Employment
    var canMoveUp: Bool = false
    var canMoveDown: Bool = false
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}

    private var isHidden: Bool {
        content.isRoleDescriptionHidden(for: employment.id)
    }

    private var hasOverride: Bool {
        content.roleDescription(for: employment.id) != nil
    }

    private var overrideBinding: Binding<String> {
        Binding(
            get: { content.employmentRoleDescriptions[employment.id] ?? "" },
            set: { newValue in
                var updated = content
                updated.setRoleDescription(newValue, for: employment.id)
                content = updated
            }
        )
    }

    private var includeBinding: Binding<Bool> {
        Binding(
            get: { !isHidden },
            set: { newValue in
                var updated = content
                updated.setRoleDescriptionHidden(!newValue, for: employment.id)
                content = updated
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Role Description")
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text("Intro line for \(employment.displayTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Toggle("Include", isOn: includeBinding)
                    .toggleStyle(.checkbox)
                    .help("Include the role description line in the generated resume")

                HStack(spacing: 4) {
                    Button(action: onMoveUp) {
                        Image(systemName: "chevron.up")
                    }
                    .controlSize(.small)
                    .disabled(!canMoveUp || isHidden)
                    .help("Move up within this section")

                    Button(action: onMoveDown) {
                        Image(systemName: "chevron.down")
                    }
                    .controlSize(.small)
                    .disabled(!canMoveDown || isHidden)
                    .help("Move down within this section")
                }

                Text(isHidden ? "Hidden" : (hasOverride ? "Custom" : "Default"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isHidden ? Color.orange : (hasOverride ? Color.blue : Color.secondary))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background((isHidden ? Color.orange : (hasOverride ? Color.blue : Color.secondary)).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if !isHidden {
                LabeledControl("Role Description") {
                    TextEditor(text: overrideBinding)
                        .font(.body.monospaced())
                        .frame(minHeight: 72)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Default")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(employment.roleDescription.trimmed.isEmpty ? "No default role description." : employment.roleDescription)
                        .font(.body.monospaced())
                        .foregroundStyle(employment.roleDescription.trimmed.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
    let document: GeneratedDocument
    let application: JobApplication
    let allDocuments: [GeneratedDocument]
    let settings: AppSettings?
    /// Compiles the existing `.tex` as-is (no re-render), preserving manual edits.
    let onRebuild: (GeneratedDocumentKind) async -> Void

    @State private var isBuilding = false

    private var kind: GeneratedDocumentKind {
        GeneratedDocumentKind(rawValue: document.kindRaw) ?? .resume
    }

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
                    FileOpenService.reveal(path: document.pdfPath)
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .disabled(!FileManager.default.fileExists(atPath: document.pdfPath))
                .controlSize(.small)
                Button {
                    isBuilding = true
                    Task {
                        await onRebuild(kind)
                        isBuilding = false
                    }
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

}

struct CuratedBulletCard: View {
    @Binding var suggestion: CuratedBulletSuggestion
    let selectedExperienceIDs: Set<UUID>
    let activeVariants: [UUID: UUID]
    let existingBulletIDs: Set<UUID>
    let existingVariantIDsByBullet: [UUID: Set<UUID>]
    let onAddToResume: () -> Void
    let onBankOnly: () -> Void
    @State private var showRelevance = false
    @State private var showHowToLearn = false
    @State private var showStory = false

    /// True when the bullet/variant actually still exists in the experience bank.
    var isStillInBank: Bool {
        guard let bulletID = suggestion.addedBulletID else { return false }
        guard existingBulletIDs.contains(bulletID) else { return false }
        if let variantID = suggestion.addedVariantID {
            return existingVariantIDsByBullet[bulletID]?.contains(variantID) ?? false
        }
        return true
    }

    /// True when the added bullet/variant is currently selected for this application's resume.
    var isInResume: Bool {
        guard isStillInBank else { return false }
        guard let bulletID = suggestion.addedBulletID else { return false }
        guard selectedExperienceIDs.contains(bulletID) else { return false }
        if let variantID = suggestion.addedVariantID {
            return activeVariants[bulletID] == variantID
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: type badge + status + bullet editor
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    // Type badge — both use blue to match the wording section's "Variant" badge
                    if suggestion.isVariation {
                        Text("Variation")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        if let title = suggestion.sourceBulletTitle {
                            Text("of \"\(title)\"")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text("New Bullet")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.teal)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.teal.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Spacer()
                    // Status badge — derived from live selection, not stored state
                    if isInResume {
                        Label("In Resume", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    } else if isStillInBank {
                        Label("In Bank", systemImage: "tray.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                TextEditor(text: $suggestion.bulletText)
                    .font(.body)
                    .frame(minHeight: 52)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
            .padding(12)

            Divider()

            // Disclosure rows
            VStack(alignment: .leading, spacing: 0) {
                CuratedBulletDisclosureRow(label: "Relevance", isExpanded: $showRelevance) {
                    Text(suggestion.relevance)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Divider()
                CuratedBulletDisclosureRow(label: "How to Learn", isExpanded: $showHowToLearn) {
                    Text(suggestion.howToLearn)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Divider()
                CuratedBulletDisclosureRow(label: "Your Story", isExpanded: $showStory) {
                    Text(suggestion.story)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Divider()

            // Action buttons — style reflects current state
            HStack(spacing: 8) {
                if isInResume {
                    Button(action: onAddToResume) {
                        Label("Re-add to Resume", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button(action: onAddToResume) {
                        Label(
                            suggestion.isVariation ? "Add Wording to Resume" : "Add to Resume",
                            systemImage: "doc.badge.plus"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if !isInResume {
                    Button(action: onBankOnly) {
                        Text(suggestion.addedState == .bankOnly ? "Re-save to Bank" : "Bank only")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isInResume
                        ? Color.green.opacity(0.4)
                        : Color(nsColor: .separatorColor).opacity(0.4),
                    lineWidth: 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.12), value: isInResume)
        .animation(.easeInOut(duration: 0.12), value: isStillInBank)
    }
}

private struct CuratedBulletDisclosureRow<Content: View>: View {
    let label: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
    }
}

struct JDAnalysisView: View {
    let text: String

    var body: some View {
        let sections = parsedSections
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
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
                        case .table(let rows):
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                                    HStack(alignment: .top, spacing: 0) {
                                        ForEach(Array(row.enumerated()), id: \.offset) { colIdx, cell in
                                            inlineText(cell)
                                                .font(rowIdx == 0 ? .body.weight(.semibold) : .body)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.vertical, 6)
                                                .padding(.horizontal, 10)
                                            if colIdx < row.count - 1 { Divider() }
                                        }
                                    }
                                    .background(rowIdx == 0 ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                                    Divider()
                                }
                            }
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

                if index < sections.count - 1 {
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
        case table([[String]])
    }

    private struct Section {
        var title: String
        var blocks: [Block]
    }

    private var parsedSections: [Section] {
        var sections: [Section] = []
        var current = Section(title: "", blocks: [])
        var pendingLines: [String] = []
        var tableRows: [[String]] = []

        func flushPending(_ lines: [String], into section: inout Section) {
            let joined = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { section.blocks.append(.paragraph(joined)) }
        }
        func flushTable(_ rows: [[String]], into section: inout Section) {
            if !rows.isEmpty { section.blocks.append(.table(rows)) }
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.hasPrefix("## ") {
                flushPending(pendingLines, into: &current)
                flushTable(tableRows, into: &current)
                pendingLines = []; tableRows = []
                if !current.title.isEmpty || !current.blocks.isEmpty { sections.append(current) }
                current = Section(title: String(line.dropFirst(3)), blocks: [])
            } else if line.hasPrefix("###") {
                flushPending(pendingLines, into: &current)
                flushTable(tableRows, into: &current)
                pendingLines = []; tableRows = []
                let heading = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if !heading.isEmpty { current.blocks.append(.subheader(heading)) }
            } else if line == "---" || line == "***" || line == "___" {
                flushPending(pendingLines, into: &current)
                flushTable(tableRows, into: &current)
                pendingLines = []; tableRows = []
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flushPending(pendingLines, into: &current)
                flushTable(tableRows, into: &current)
                pendingLines = []; tableRows = []
                let content = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                current.blocks.append(.bullet(content))
            } else if line.hasPrefix("|") {
                flushPending(pendingLines, into: &current)
                pendingLines = []
                let cells = line.components(separatedBy: "|").dropFirst().dropLast()
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                let isSeparator = !cells.isEmpty && cells.filter { !$0.isEmpty }.allSatisfy { cell in
                    cell.allSatisfy { $0 == "-" || $0 == ":" }
                }
                if !isSeparator { tableRows.append(Array(cells)) }
            } else if line.isEmpty {
                flushPending(pendingLines, into: &current)
                flushTable(tableRows, into: &current)
                pendingLines = []; tableRows = []
            } else {
                flushTable(tableRows, into: &current)
                tableRows = []
                pendingLines.append(line)
            }
        }
        flushPending(pendingLines, into: &current)
        flushTable(tableRows, into: &current)
        if !current.title.isEmpty || !current.blocks.isEmpty { sections.append(current) }
        return sections
    }
}
