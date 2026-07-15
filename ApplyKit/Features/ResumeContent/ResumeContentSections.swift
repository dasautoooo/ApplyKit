//
//  ResumeContentSections.swift
//  ApplyKit
//
//  Generic resume-content editor sections shared by the application editor
//  and the master resume editor. Each view binds to any `ResumeContentModel`.
//

import AppKit
import SwiftUI

/// Summary text (optional; omitted from the resume when blank).
struct ResumeSummarySection<Content: ResumeContentModel>: View {
    @Binding var content: Content

    var body: some View {
        DetailPanel("Summary") {
            VStack(alignment: .leading, spacing: 4) {
                TextEditor(text: $content.summaryText)
                    .font(.body.monospaced())
                    .frame(minHeight: 90)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                    )
                Text("Optional — leave blank to omit the summary from this resume.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Skills override (falls back to the global block when blank).
struct ResumeSkillsSection<Content: ResumeContentModel>: View {
    @Binding var content: Content
    let globalSkillsBlock: String

    var body: some View {
        DetailPanel("Skills", trailing: {
            Text(content.hasSkillsOverride ? "Custom" : "Default")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(content.hasSkillsOverride ? Color.blue : Color.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background((content.hasSkillsOverride ? Color.blue : Color.secondary).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }) {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $content.skillsBlockText)
                    .font(.body.monospaced())
                    .frame(minHeight: 90)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                    )

                Text("Leave blank to use the global skills block from Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Global default")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(globalSkillsBlock.trimmed.isEmpty ? "No global skills block set." : globalSkillsBlock)
                        .font(.body.monospaced())
                        .foregroundStyle(globalSkillsBlock.trimmed.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }
}

/// Resume section ordering (Summary, Education, Experience, Selected Projects,
/// Skills). Mirrors the up/down chevron reorder pattern used for experience
/// bullets in `ExperienceWordingRow`.
struct ResumeSectionOrderSection<Content: ResumeContentModel>: View {
    @Binding var content: Content

    var body: some View {
        DetailPanel("Section Order") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(content.sectionOrder.enumerated()), id: \.element) { index, section in
                    HStack {
                        Text(section.rawValue)
                            .font(.callout)
                        Spacer()
                        HStack(spacing: 4) {
                            Button {
                                moveSectionOrder(from: index, to: index - 1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .disabled(index == 0)
                            .help("Move up")

                            Button {
                                moveSectionOrder(from: index, to: index + 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .disabled(index == content.sectionOrder.count - 1)
                            .help("Move down")
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 5)
                    if index < content.sectionOrder.count - 1 {
                        Divider()
                    }
                }
                Text("Controls the order sections appear in the generated resume.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func moveSectionOrder(from: Int, to: Int) {
        var order = content.sectionOrder
        guard order.indices.contains(to) else { return }
        order.swapAt(from, to)
        var updated = content
        updated.setSectionOrder(order)
        content = updated
    }
}

/// Work/education bullet selection, grouped by employment. `accessory` slots in
/// caller-specific controls (e.g. the application editor's AI suggestion button).
struct ResumeExperienceSelectionSection<Content: ResumeContentModel, Accessory: View>: View {
    @Binding var content: Content
    let experiences: [ExperienceBullet]
    let employments: [Employment]
    @ViewBuilder var accessory: Accessory

    var body: some View {
        DetailPanel("Experience Source") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Work and education bullets used in the resume Experience section and Codex prompts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                accessory

                if experiences.isEmpty {
                    Text("No experience items yet.")
                        .foregroundStyle(.secondary)
                } else {
                    // Decode the selected-ID set once per render instead of inside every row's binding.
                    let selectedExperienceIDs = content.selectedExperienceIDs
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(ResumeContentGrouping.selectionGroups(experiences: experiences, employments: employments), id: \.title) { group in
                            SelectionGroupView(title: group.title) {
                                ForEach(group.bullets) { experience in
                                    SelectionToggleRow(
                                        title: experience.displayTitle,
                                        detail: [experience.skillsText].filter { !$0.trimmed.isEmpty }.joined(separator: " - "),
                                        isOn: Binding(
                                            get: { selectedExperienceIDs.contains(experience.id) },
                                            set: { newValue in
                                                var updated = content
                                                updated.setExperience(experience.id, selected: newValue)
                                                content = updated
                                            }
                                        )
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Project/open-source bullet selection for the Selected Projects section.
struct ResumeProjectSelectionSection<Content: ResumeContentModel>: View {
    @Binding var content: Content
    let experiences: [ExperienceBullet]
    let employments: [Employment]

    var body: some View {
        DetailPanel("Selected Projects") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Projects render separately from work experience in the Selected Projects section.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let groups = ResumeContentGrouping.projectSelectionGroups(experiences: experiences, employments: employments)
                if groups.isEmpty {
                    Text("No personal, project, or open-source items yet. Add personal projects in Experience Bank.")
                        .foregroundStyle(.secondary)
                } else {
                    // Decode the selected-ID set once per render instead of inside every row's binding.
                    let selectedProjectIDs = content.selectedProjectIDs
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(groups, id: \.title) { group in
                            SelectionGroupView(title: group.title) {
                                ForEach(group.bullets) { project in
                                    SelectionToggleRow(
                                        title: project.displayTitle,
                                        detail: [project.company, project.skillsText].filter { !$0.trimmed.isEmpty }.joined(separator: " - "),
                                        isOn: Binding(
                                            get: { selectedProjectIDs.contains(project.id) },
                                            set: { newValue in
                                                var updated = content
                                                updated.setProject(project.id, selected: newValue)
                                                content = updated
                                            }
                                        )
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Per-bullet wording (base/variant), role-description overrides, and bullet
/// reordering for the selected experiences and projects.
struct ResumeWordingSection<Content: ResumeContentModel & Identifiable>: View where Content.ID == UUID {
    @Binding var content: Content
    let experiences: [ExperienceBullet]
    let employments: [Employment]
    let applications: [JobApplication]
    let settings: AppSettings?
    /// Builds the AI refinement prompt for a bullet; nil hides "Refine with AI"
    /// (master resumes have no job description to refine against).
    let refinePrompt: ((ExperienceBullet) -> String)?
    let experienceBinding: (UUID) -> Binding<ExperienceBullet>
    let onPersistExperience: (ExperienceBullet) -> Void
    let onPersistApplication: (JobApplication) -> Void
    let onPersistContent: (Content) -> Void

    var body: some View {
        DetailPanel("Tailor Experience") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Each job groups its selected bullets below. Set the role description, choose base wording or a named variant per bullet, and reorder bullets within the job.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let groups = ResumeContentGrouping.wordingGroups(content: content, experiences: experiences, employments: employments)
                if groups.isEmpty {
                    Text("Select an experience or project above to tune its wording.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(groups) { group in
                            wordingGroupCard(group, groups: groups)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func wordingGroupCard(_ group: WordingGroup, groups: [WordingGroup]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Group header — names the employment (or project bucket) the items belong to.
            if let employment = group.employment {
                HStack(spacing: 8) {
                    Image(systemName: "briefcase.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(employment.displayTitle)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text([employment.role, employment.dateRangeText()].filter { !$0.trimmed.isEmpty }.joined(separator: " - "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: group.isProject ? "folder.fill" : "tray.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(group.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                }
            }

            Divider()

            // Items (role description + bullets), indented behind a left accent rule to
            // show they belong to this job. All reorder together via the shared order.
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                        switch item {
                        case .roleDescription(let employment):
                            RoleDescriptionRow(
                                content: $content,
                                employment: employment,
                                canMoveUp: index > 0,
                                canMoveDown: index < group.items.count - 1,
                                onMoveUp: { moveExperience(item.id, in: group, groups: groups, by: -1) },
                                onMoveDown: { moveExperience(item.id, in: group, groups: groups, by: 1) }
                            )
                        case .bullet(let experience):
                            ExperienceWordingRow(
                                content: $content,
                                experience: experienceBinding(experience.id),
                                applications: applications,
                                settings: settings,
                                refinePrompt: refinePrompt,
                                onPersistExperience: onPersistExperience,
                                onPersistApplication: onPersistApplication,
                                onPersistContent: onPersistContent,
                                canMoveUp: index > 0,
                                canMoveDown: index < group.items.count - 1,
                                onMoveUp: { moveExperience(experience.id, in: group, groups: groups, by: -1) },
                                onMoveDown: { moveExperience(experience.id, in: group, groups: groups, by: 1) }
                            )
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Reorder a bullet within its wording group by ±1, persisting the stored order.
    private func moveExperience(_ id: UUID, in group: WordingGroup, groups: [WordingGroup], by delta: Int) {
        guard let fullOrder = ResumeContentGrouping.experienceOrderMoving(id, in: group, by: delta, groups: groups) else { return }
        var updated = content
        updated.setExperienceOrder(fullOrder)
        content = updated
        onPersistContent(updated)
    }
}
