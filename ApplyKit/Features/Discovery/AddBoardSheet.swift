//
//  AddBoardSheet.swift
//  ApplyKit
//
//  Add or edit a tracked job board: paste a board/job URL to auto-detect the ATS
//  provider and company (via ATSBoardResolver.board(for:)), then set optional
//  keyword filters. Used by DiscoveryWorkspaceView.
//

import SwiftUI

struct AddBoardSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// When non-nil, the sheet edits an existing board (URL detection is skipped).
    let existing: TrackedBoard?
    /// Provider ids already tracked, so listed companies show as added.
    var trackedProviderIDs: Set<String> = []
    let onSave: (TrackedBoard) -> Void

    @State private var urlText = ""
    @State private var detected: TrackedBoard?
    @State private var detectError = ""
    @State private var companyName = ""
    @State private var titleKeywords = ""
    @State private var excludeKeywords = ""
    @State private var locationKeywords = ""
    @State private var mode: Mode = .url
    @State private var companyQuery = ""
    /// Set once a company is chosen from the list — the sheet then shows its
    /// filter form rather than tracking it immediately.
    @State private var pickedCompany: BuiltInCompany?

    private enum Mode: String, CaseIterable, Identifiable {
        case url = "From URL"
        case company = "Browse Companies"
        var id: String { rawValue }
    }

    private var isEditing: Bool { existing != nil }

    private var isBrowsingCompanies: Bool {
        !isEditing && mode == .company && pickedCompany == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if !isEditing, pickedCompany == nil {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .onChange(of: mode) { _, _ in
                    detected = nil
                    detectError = ""
                }
            }

            if isBrowsingCompanies {
                companyList
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let pickedCompany {
                            // Came from the company list: no URL to show, but let
                            // the user step back and choose a different employer.
                            HStack {
                                Button {
                                    self.pickedCompany = nil
                                    detected = nil
                                    resetFilterFields()
                                } label: {
                                    Label("All companies", systemImage: "chevron.left")
                                }
                                .buttonStyle(.link)
                                Spacer()
                            }
                            Text(pickedCompany.note)
                                .font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            providerSummary
                        } else if isEditing {
                            providerSummary
                        } else {
                            urlEntry
                            if detected != nil { providerSummary }
                        }
                        if isEditing || detected != nil {
                            detailsForm
                        }
                    }
                    .padding(20)
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 540, idealWidth: 580, minHeight: 460, idealHeight: 520)
        .onAppear(perform: prime)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(isEditing ? "Edit Tracked Board" : "Track a Job Board")
                .font(.headline)
            Text(isEditing
                 ? "Adjust the keyword filters for this board."
                 : "Paste any ATS board URL, or pick a large employer that runs its own career site.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    // MARK: - Company list

    private var companyList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search companies", text: $companyQuery).textFieldStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: .separatorColor).opacity(0.4)))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 20).padding(.vertical, 12)

            let results = BuiltInCompanies.search(companyQuery)
            if results.isEmpty {
                ContentUnavailableView("No matches", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(results) { company in
                            companyRow(company)
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func companyRow(_ company: BuiltInCompany) -> some View {
        let isTracked = trackedProviderIDs.contains(company.id)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(company.name).font(.body.weight(.medium))
                Text(company.note)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if isTracked {
                Label("Tracked", systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(.green)
            } else {
                Button("Track…") { pick(company) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture { if !isTracked { pick(company) } }
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isTracked ? Color.green.opacity(0.07) : Color.clear)
        )
        .contextMenu {
            Button("Open Careers Page") {
                if let url = URL(string: company.careersURL) { NSWorkspace.shared.open(url) }
            }
        }
    }

    private var urlEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Board or job URL")
                .font(.subheadline.weight(.medium))
            HStack {
                TextField("https://boards.greenhouse.io/acme", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(detect)
                Button("Detect", action: detect)
                    .disabled(urlText.trimmed.isEmpty)
            }
            if !detectError.isEmpty {
                Label(detectError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder private var providerSummary: some View {
        if let board = existing ?? detected {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text("Detected **\(board.providerName)** board")
                Text("·").foregroundStyle(.secondary)
                Text(board.slug).font(.callout.monospaced()).foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    private var detailsForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Company name", text: $companyName, placeholder: "Acme Inc.")
            field("Title includes (comma-separated)", text: $titleKeywords,
                  placeholder: "engineer, developer", help: "Only postings whose title contains one of these. Empty = all titles.")
            field("Title excludes (comma-separated)", text: $excludeKeywords,
                  placeholder: "senior, staff", help: "Drop postings whose title contains any of these.")
            field("Location includes (comma-separated)", text: $locationKeywords,
                  placeholder: "remote, new york", help: "Only postings whose location contains one of these. Empty = all locations.")
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String, help: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline.weight(.medium))
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
            if let help {
                Text(help).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            // While browsing the company list there's nothing staged to commit yet.
            if !isBrowsingCompanies {
                Button(isEditing ? "Save" : "Track Board", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(existing == nil && detected == nil)
            }
        }
        .padding(16)
    }

    // MARK: - Actions

    /// Stage a company for configuration. `detected` drives the shared summary +
    /// filter form and is what `save()` commits, so the company path reuses the
    /// exact same flow as URL detection.
    private func pick(_ company: BuiltInCompany) {
        pickedCompany = company
        detected = company.makeBoard()
        companyName = company.name
        detectError = ""
    }

    private func resetFilterFields() {
        companyName = ""
        titleKeywords = ""
        excludeKeywords = ""
        locationKeywords = ""
    }

    private func prime() {
        guard let existing else { return }
        companyName = existing.companyName
        titleKeywords = existing.titleKeywords.joined(separator: ", ")
        excludeKeywords = existing.excludeKeywords.joined(separator: ", ")
        locationKeywords = existing.locationKeywords.joined(separator: ", ")
    }

    private func detect() {
        detectError = ""
        detected = nil
        guard let url = try? JobURLNormalizer.validatedURL(from: urlText) else {
            detectError = "Enter a complete URL, including https://."
            return
        }
        guard let board = ATSBoardResolver.board(for: url) else {
            detectError = "That URL isn't a recognized job board. Supported: Greenhouse, Lever, Ashby, Workday, SmartRecruiters, Workable, Recruitee, Personio, BambooHR, Breezy, JazzHR, Teamtailor — plus major employers' own career sites."
            return
        }
        detected = board
        if companyName.trimmed.isEmpty { companyName = board.companyName }
    }

    private func save() {
        guard var board = existing ?? detected else { return }
        board.companyName = companyName.trimmed.isEmpty ? board.slug : companyName.trimmed
        board.titleKeywords = titleKeywords.commaSeparatedValues
        board.excludeKeywords = excludeKeywords.commaSeparatedValues
        board.locationKeywords = locationKeywords.commaSeparatedValues
        onSave(board)
        dismiss()
    }
}
