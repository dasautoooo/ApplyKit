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

        let profileSection = """
        ## My Profile
        \([field("Name", profile.fullName),
           field("Email", profile.email),
           field("Phone", profile.phone),
           field("City", profile.city),
           field("LinkedIn", profile.linkedin),
           field("GitHub", profile.github),
           field("Website", profile.website)].filter { !$0.isEmpty }.joined(separator: "\n"))
        \(profile.skillsBlock.trimmed.isEmpty ? "" : "\n### Skills\n\(profile.skillsBlock)")
        \(profile.educationBlock.trimmed.isEmpty ? "" : "\n### Education\n\(profile.educationBlock)")
        """

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

        // Resume-style experience: bullets grouped by employment (then unassigned, then
        // projects) and ordered exactly as in the editor, via the shared `wordingGroups`.
        let experienceSection: String = {
            let groups = wordingGroups.filter { !$0.bullets.isEmpty }
            if groups.isEmpty { return "## Experience\nNone selected." }
            let blocks = groups.map { group -> String in
                var lines: [String] = []
                if let emp = group.employment {
                    lines.append("### \(emp.summaryLine)")
                    if !emp.location.trimmed.isEmpty { lines.append("Location: \(emp.location)") }
                    if let override = application.roleDescription(for: emp.id) {
                        if !emp.roleDescription.trimmed.isEmpty {
                            lines.append("Role description (default): \(emp.roleDescription)")
                        }
                        lines.append("Role description (override for this application): \(override)")
                    } else if !emp.roleDescription.trimmed.isEmpty {
                        lines.append("Role description: \(emp.roleDescription)")
                    }
                } else {
                    lines.append("### \(group.title)")
                }
                for exp in group.bullets {
                    let bullet = exp.bulletText(variantID: application.selectedVariantID(for: exp.id))
                    lines.append("- \(bullet)")
                    if !exp.skillsText.trimmed.isEmpty { lines.append("  Skills: \(exp.skillsText)") }
                }
                return lines.joined(separator: "\n")
            }.joined(separator: "\n\n")
            return "## Experience\n\(blocks)"
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
        parts.append(profileSection)
        parts.append(experienceSection)
        if !application.notes.trimmed.isEmpty {
            parts.append("## Notes\n\(application.notes)")
        }

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
                        settings: settings
                    )
                }
            }
        }
    }


}
