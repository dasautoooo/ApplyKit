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
