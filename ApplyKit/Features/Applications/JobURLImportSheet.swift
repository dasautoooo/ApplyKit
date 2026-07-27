import AppKit
import SwiftUI

struct JobURLImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppActivityMonitor.self) private var activityMonitor

    let settings: AppSettings
    let masterResumes: [MasterResume]
    let experiences: [ExperienceBullet]
    let existingApplications: [JobApplication]
    let onCreate: (JobImportDraft, MasterResume) throws -> Void

    @State private var urlText = ""
    @State private var pastedDescription = ""
    @State private var draft: JobImportDraft?
    @State private var isWorking = false
    @State private var errorMessage = ""

    private let coordinator = JobImportCoordinator()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                if let draft {
                    JobImportPreview(
                        draft: Binding(
                            get: { self.draft ?? draft },
                            set: { self.draft = $0 }
                        ),
                        masterResumes: masterResumes,
                        duplicateApplication: duplicateApplication(for: draft.jobURL)
                    )
                } else {
                    entryContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(minWidth: 720, idealWidth: 780, minHeight: 620, idealHeight: 760)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text("Import from Job URL")
                    .font(.title2.weight(.semibold))
                Text(draft == nil
                     ? "ApplyKit will extract the posting and recommend a master resume."
                     : "Review every field before creating the application.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var entryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if masterResumes.isEmpty {
                    blockingMessage(
                        title: "A master resume is required",
                        message: "Create at least one preset in Master Resumes, then return here to import the job."
                    )
                } else if !AIBackendRunner.isConfigured(settings) {
                    blockingMessage(
                        title: "Configure an AI backend",
                        message: "Add Claude Code or Codex in Settings → Tools before importing a job."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Job posting URL")
                            .font(.headline)
                        TextField("https://company.com/jobs/…", text: $urlText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { startImport() }
                        Text("Public company and ATS pages work best. Login, CAPTCHA, and blocked pages can use the manual fallback below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if isWorking {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Reading the job page and matching your master resumes…")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else {
                        Button {
                            startImport()
                        } label: {
                            Label("Read Job Posting", systemImage: "sparkles")
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(urlText.trimmed.isEmpty)
                    }

                    if !errorMessage.isEmpty {
                        manualFallback
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func blockingMessage(title: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity, minHeight: 340)
    }

    private var manualFallback: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Open in Browser") {
                    if let url = try? JobURLNormalizer.validatedURL(from: urlText) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .disabled((try? JobURLNormalizer.validatedURL(from: urlText)) == nil)

                Button("Retry Page") { startImport() }
                    .disabled(urlText.trimmed.isEmpty)
            }

            Text("Paste the job description")
                .font(.headline)
            TextEditor(text: $pastedDescription)
                .font(.body.monospaced())
                .frame(minHeight: 220)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                }

            Button {
                parsePastedDescription()
            } label: {
                Label("Parse Pasted JD", systemImage: "doc.text.magnifyingglass")
            }
            .disabled(pastedDescription.trimmed.count < 80 || urlText.trimmed.isEmpty)
        }
        .padding(16)
        .background(Color.orange.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            if draft != nil, !errorMessage.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Spacer()

            if let draft {
                Button("Start Over") {
                    self.draft = nil
                    errorMessage = ""
                }

                Button("Create Application") {
                    createApplication(from: draft)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate(draft))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func startImport() {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = ""
        activityMonitor.start("Importing job posting…")
        Task {
            do {
                let result = try await coordinator.importURL(
                    urlText,
                    masterResumes: masterResumes,
                    experiences: experiences,
                    settings: settings
                )
                draft = result
                isWorking = false
                activityMonitor.succeed("Job posting ready to review.")
            } catch {
                isWorking = false
                errorMessage = error.localizedDescription
                activityMonitor.fail(error.localizedDescription)
            }
        }
    }

    private func parsePastedDescription() {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = ""
        activityMonitor.start("Parsing pasted job description…")
        Task {
            do {
                let result = try await coordinator.importPastedDescription(
                    pastedDescription,
                    urlValue: urlText,
                    masterResumes: masterResumes,
                    experiences: experiences,
                    settings: settings
                )
                draft = result
                isWorking = false
                activityMonitor.succeed("Pasted job description ready to review.")
            } catch {
                isWorking = false
                errorMessage = error.localizedDescription
                activityMonitor.fail(error.localizedDescription)
            }
        }
    }

    private func canCreate(_ draft: JobImportDraft) -> Bool {
        !draft.companyName.trimmed.isEmpty
            && !draft.jobTitle.trimmed.isEmpty
            && draft.jobDescription.trimmed.count >= 80
            && draft.selectedMasterResumeID != nil
    }

    private func createApplication(from draft: JobImportDraft) {
        guard let selectedID = draft.selectedMasterResumeID,
              let masterResume = masterResumes.first(where: { $0.id == selectedID }) else { return }
        do {
            try onCreate(draft, masterResume)
            activityMonitor.succeed("Created \(draft.companyName) — \(draft.jobTitle).")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            activityMonitor.fail(error.localizedDescription)
        }
    }

    private func duplicateApplication(for url: String) -> JobApplication? {
        guard let key = JobURLNormalizer.duplicateKey(for: url) else { return nil }
        return existingApplications.first { JobURLNormalizer.duplicateKey(for: $0.jobURL) == key }
    }
}

private struct JobImportPreview: View {
    @Binding var draft: JobImportDraft
    let masterResumes: [MasterResume]
    let duplicateApplication: JobApplication?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let duplicateApplication {
                    Label(
                        "This URL is already used by \(duplicateApplication.displayTitle). You can still create another application.",
                        systemImage: "doc.on.doc"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(12)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if draft.wasRendered {
                    Label("This posting required browser rendering.", systemImage: "safari")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GroupBox("Role") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                        row("Company") {
                            TextField("Company", text: $draft.companyName)
                        }
                        row("Job title") {
                            TextField("Job title", text: $draft.jobTitle)
                        }
                        row("URL") {
                            TextField("URL", text: $draft.jobURL)
                        }
                        row("Location") {
                            TextField("Location", text: $draft.location)
                        }
                        row("Work mode") {
                            Picker("Work mode", selection: $draft.workModeRaw) {
                                ForEach(WorkMode.allCases) { option in
                                    Text(option.rawValue).tag(option.rawValue)
                                }
                            }
                            .labelsHidden()
                        }
                        row("Employment") {
                            Picker("Employment", selection: $draft.employmentTypeRaw) {
                                ForEach(EmploymentType.allCases) { option in
                                    Text(option.rawValue).tag(option.rawValue)
                                }
                            }
                            .labelsHidden()
                        }
                        row("Source") {
                            Picker("Source", selection: $draft.sourceRaw) {
                                ForEach(ApplicationSource.allCases) { option in
                                    Text(option.rawValue).tag(option.rawValue)
                                }
                            }
                            .labelsHidden()
                        }
                        row("Deadline") {
                            HStack {
                                Toggle("Has deadline", isOn: deadlineEnabled)
                                if draft.deadline != nil {
                                    DatePicker(
                                        "Deadline",
                                        selection: deadlineBinding,
                                        displayedComponents: .date
                                    )
                                    .labelsHidden()
                                }
                            }
                        }
                    }
                    .padding(8)
                }

                GroupBox("Master Resume") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Preset", selection: $draft.selectedMasterResumeID) {
                            Text("Choose a master resume…").tag(nil as UUID?)
                            ForEach(masterResumes) { resume in
                                Text(resume.displayTitle).tag(resume.id as UUID?)
                            }
                        }

                        if let recommendation = draft.recommendedMatch,
                           let resume = masterResumes.first(where: { $0.id == recommendation.masterResumeID }) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: draft.hasHighConfidenceRecommendation ? "checkmark.seal.fill" : "questionmark.diamond.fill")
                                    .foregroundStyle(draft.hasHighConfidenceRecommendation ? .green : .orange)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Recommended: \(resume.displayTitle) · \(Int(recommendation.confidence * 100))%")
                                        .font(.callout.weight(.semibold))
                                    Text(recommendation.rationale.isEmpty
                                         ? "Review the recommendation before creating the application."
                                         : recommendation.rationale)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Text("The importer could not confidently match a preset. Choose one before creating the application.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(8)
                }

                GroupBox("Job Description") {
                    TextEditor(text: $draft.jobDescription)
                        .font(.body.monospaced())
                        .frame(minHeight: 260)
                        .padding(4)
                }
            }
            .padding(24)
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var deadlineEnabled: Binding<Bool> {
        Binding(
            get: { draft.deadline != nil },
            set: { draft.deadline = $0 ? (draft.deadline ?? Date()) : nil }
        )
    }

    private var deadlineBinding: Binding<Date> {
        Binding(
            get: { draft.deadline ?? Date() },
            set: { draft.deadline = $0 }
        )
    }
}
