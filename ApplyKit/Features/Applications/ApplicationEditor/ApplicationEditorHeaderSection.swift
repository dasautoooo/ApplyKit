//
//  ApplicationEditorHeaderSection.swift
//  ApplyKit
//

import AppKit
import SwiftUI

extension ApplicationEditorView {
    var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Company", text: $application.companyName)
                        .font(.system(size: 26, weight: .semibold))
                        .textFieldStyle(.plain)
                    TextField("Job title", text: $application.jobTitle)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textFieldStyle(.plain)
                }

                Spacer(minLength: 16)

                HStack(spacing: 8) {
                    Menu {
                        Button {
                            copyContext(includeAnalysis: false)
                        } label: {
                            Label("Copy without JD Analysis", systemImage: "doc.on.clipboard")
                        }
                    } label: {
                        Label("Copy Context", systemImage: "doc.on.clipboard")
                    } primaryAction: {
                        copyContext(includeAnalysis: true)
                    }
                    .menuStyle(.button)
                    .fixedSize()
                    .help("Copy all application info as a prompt you can paste into ChatGPT or Claude")

                    if application.isArchived {
                        Label("Archived", systemImage: "archivebox")
                            .foregroundStyle(.secondary)

                        Button {
                            onRestore()
                        } label: {
                            Label("Restore", systemImage: "tray.and.arrow.up")
                        }
                    } else {
                        Button {
                            onArchive()
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                    }

                    Button(role: .destructive) {
                        onDeleteRequest()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

        }
        .padding(.bottom, 2)
    }

    var roleForm: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                LabeledControl("Status") {
                    Picker("Status", selection: $application.statusRaw) {
                        ForEach(ApplicationStatus.allCases) { status in
                            Text(status.rawValue).tag(status.rawValue)
                        }
                    }
                }

                LabeledControl("Priority") {
                    Picker("Priority", selection: $application.priorityRaw) {
                        ForEach(ApplicationPriority.allCases) { priority in
                            Text(priority.rawValue).tag(priority.rawValue)
                        }
                    }
                }

                LabeledControl("Work mode") {
                    Picker("Work mode", selection: $application.workModeRaw) {
                        ForEach(WorkMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode.rawValue)
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                LabeledControl("Employment") {
                    Picker("Employment", selection: $application.employmentTypeRaw) {
                        ForEach(EmploymentType.allCases) { type in
                            Text(type.rawValue).tag(type.rawValue)
                        }
                    }
                }

                LabeledControl("Source") {
                    Picker("Source", selection: $application.sourceRaw) {
                        ForEach(ApplicationSource.allCases) { source in
                            Text(source.rawValue).tag(source.rawValue)
                        }
                    }
                }

                LabeledControl("Location") {
                    TextField("Location", text: $application.location)
                        .textFieldStyle(.roundedBorder)
                }
            }

            LabeledControl("Job URL") {
                HStack(spacing: 8) {
                    TextField("https://", text: $application.jobURL)
                        .textFieldStyle(.roundedBorder)
                    if !application.jobURL.trimmed.isEmpty {
                        Button {
                            if let url = URL(string: application.jobURL) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Label("Open", systemImage: "arrow.up.forward.square")
                        }
                    }
                }
            }

            LabeledControl("Next action") {
                TextField("Follow up, apply, ask for referral...", text: $application.nextAction)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(alignment: .top, spacing: 16) {
                LabeledControl("Referral") {
                    TextField("Referral contact", text: $application.referralContact)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledControl("Recruiter") {
                    TextField("Recruiter contact", text: $application.recruiterContact)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(alignment: .center, spacing: 20) {
                OptionalDatePicker(title: "Applied", date: $application.dateApplied)
                OptionalDatePicker(title: "Deadline", date: $application.deadline)
                Toggle("Cover letter needed", isOn: $application.coverLetterNeeded)
                Spacer()
            }
        }
    }

    func copyContext(includeAnalysis: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(applicationContextText(includeAnalysis: includeAnalysis), forType: .string)
    }

    func applicationContextText(includeAnalysis: Bool) -> String {
        let profile = store.profile
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none

        func date(_ d: Date?) -> String { d.map { fmt.string(from: $0) } ?? "N/A" }
        func field(_ label: String, _ value: String) -> String {
            value.trimmed.isEmpty ? "" : "\(label): \(value)"
        }

        let appSection = """
        ## Application Details
        \([field("Company", application.companyName),
           field("Role", application.jobTitle),
           field("Location", application.location),
           field("Work Mode", application.workModeRaw),
           field("Employment Type", application.employmentTypeRaw),
           field("Job URL", application.jobURL),
           field("Status", application.statusRaw),
           field("Priority", application.priorityRaw),
           field("Source", application.sourceRaw),
           field("Applied", date(application.dateApplied)),
           field("Deadline", date(application.deadline)),
           field("Referral Contact", application.referralContact),
           field("Recruiter Contact", application.recruiterContact),
           field("Next Action", application.nextAction),
           "Cover letter needed: \(application.coverLetterNeeded ? "Yes" : "No")"].filter { !$0.isEmpty }.joined(separator: "\n"))
        """

        // Resume content — mirrors exactly what ResumeRenderer produces for this application:
        // effective role descriptions + selected-variant bullet text, per-application summary
        // and skills, in the same section order as the resume template.
        let resumeSection: String = {
            var blocks: [String] = []

            // Contact — matches the resume header (name + the two address lines).
            let contactLines = [
                field("Name", profile.fullName),
                [profile.city, profile.phone, profile.email].filter { !$0.trimmed.isEmpty }.joined(separator: " | "),
                [profile.linkedin, profile.github, profile.website].filter { !$0.trimmed.isEmpty }.joined(separator: " | ")
            ].filter { !$0.trimmed.isEmpty }
            if !contactLines.isEmpty { blocks.append("### Contact\n\(contactLines.joined(separator: "\n"))") }

            // The remaining sections are keyed by kind so they can be joined in the
            // application's configured resume section order (see `sectionOrderSection`).
            var sectionBlocks: [ResumeSectionKind: String] = [:]

            // Summary (per-application; omitted when blank, like the resume).
            if application.hasSummary { sectionBlocks[.summary] = "### Summary\n\(application.summaryText)" }

            // Education.
            if !profile.educationBlock.trimmed.isEmpty { sectionBlocks[.education] = "### Education\n\(profile.educationBlock)" }

            // Experience — grouped by employment; skip unassigned/orphan bullets (not on the resume).
            let experienceGroups = wordingGroups.filter { !$0.isProject && $0.employment != nil && !$0.bullets.isEmpty }
            if !experienceGroups.isEmpty {
                let body = experienceGroups.map { group -> String in
                    let emp = group.employment!
                    let header = emp.location.trimmed.isEmpty ? emp.summaryLine : "\(emp.summaryLine), \(emp.location)"
                    var lines = ["#### \(header)"]
                    for item in group.items {
                        switch item {
                        case .roleDescription(let employment):
                            guard !application.isRoleDescriptionHidden(for: employment.id) else { continue }
                            let role = application.roleDescription(for: employment.id) ?? employment.roleDescription
                            if !role.trimmed.isEmpty { lines.append("- \(role)") }
                        case .bullet(let bullet):
                            lines.append("- \(bullet.bulletText(variantID: application.selectedVariantID(for: bullet.id)))")
                        }
                    }
                    return lines.joined(separator: "\n")
                }.joined(separator: "\n\n")
                sectionBlocks[.experience] = "### Experience\n\(body)"
            }

            // Selected Projects — each project as its own titled entry (mirrors ResumeRenderer.projectBlock).
            let projects = wordingGroups.filter(\.isProject).flatMap(\.bullets)
            if !projects.isEmpty {
                let body = projects.map { proj -> String in
                    let title = proj.resumeDisplayName.trimmed.isEmpty ? proj.displayTitle : proj.resumeDisplayName
                    let bulletLines = proj.bulletText(variantID: application.selectedVariantID(for: proj.id))
                        .split(separator: "\n").map { String($0).trimmed }.filter { !$0.isEmpty }
                        .map { "- \($0)" }.joined(separator: "\n")
                    return bulletLines.isEmpty ? "#### \(title)" : "#### \(title)\n\(bulletLines)"
                }.joined(separator: "\n\n")
                sectionBlocks[.projects] = "### Selected Projects\n\(body)"
            }

            // Skills — effective per-application value (override else global).
            let skills = application.effectiveSkillsBlock(default: profile.skillsBlock)
            if !skills.trimmed.isEmpty { sectionBlocks[.skills] = "### Skills\n\(skills)" }

            blocks += application.sectionOrder.compactMap { sectionBlocks[$0] }

            return "## Resume\n\(blocks.joined(separator: "\n\n"))"
        }()

        var parts: [String] = [
            "# Application Context: \(application.displayTitle)",
            appSection,
        ]
        if !application.jobDescription.trimmed.isEmpty {
            parts.append("## Job Description\n\(application.jobDescription)")
        }
        if includeAnalysis, !application.jdAnalysisText.trimmed.isEmpty {
            parts.append("## JD Analysis\n\(application.jdAnalysisText)")
        }
        if !application.notes.trimmed.isEmpty {
            parts.append("## Notes\n\(application.notes)")
        }
        parts.append(resumeSection)

        return parts.joined(separator: "\n\n---\n\n")
    }

    var documentActions: some View {
        DetailPanel("Documents") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button {
                        Task { await generateDocument(.resume, replacingExisting: hasGeneratedDocument(.resume)) }
                    } label: {
                        Label(
                            documentActionTitle(for: .resume),
                            systemImage: "doc.badge.plus"
                        )
                    }
                    .disabled(activityMonitor.state == .running)

                    Button {
                        Task { await generateDocument(.coverLetter, replacingExisting: hasGeneratedDocument(.coverLetter)) }
                    } label: {
                        Label(
                            documentActionTitle(for: .coverLetter),
                            systemImage: "envelope.badge"
                        )
                    }
                    .disabled(activityMonitor.state == .running)

                    Spacer()
                }

                ForEach(documents) { document in
                    DocumentRow(
                        document: document,
                        application: application,
                        allDocuments: documents,
                        settings: settings,
                        onRebuild: { _ in await rebuildDocument(document, allDocuments: documents) }
                    )
                }
            }
        }
    }


}
