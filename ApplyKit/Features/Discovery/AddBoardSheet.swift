//
//  AddBoardSheet.swift
//  ApplyKit
//
//  Add or edit tracked job boards, three ways: paste a board/job URL to
//  auto-detect the ATS provider (via ATSBoardResolver.board(for:)), pick a
//  large employer that runs its own career site, or paste a whole watchlist
//  and add it in bulk. Used by DiscoveryWorkspaceView.
//

import SwiftUI

struct AddBoardSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// When non-nil, the sheet edits an existing board (URL detection is skipped).
    let existing: TrackedBoard?
    /// Every board already tracked — used to show listed companies as added,
    /// and to recognize a watchlist name that's already being tracked.
    var trackedBoards: [TrackedBoard] = []
    /// Takes a batch: the watchlist mode adds boards by the dozen, and a poll
    /// per board would put dozens of crawls in flight at once.
    let onSave: ([TrackedBoard]) -> Void

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
        case watchlist = "Paste a List"
        var id: String { rawValue }
    }

    private var isEditing: Bool { existing != nil }

    private var isBrowsingCompanies: Bool {
        !isEditing && mode == .company && pickedCompany == nil
    }

    private var isPastingList: Bool { !isEditing && mode == .watchlist }

    private var trackedBoardKeys: Set<String> { Set(trackedBoards.map(\.trackingKey)) }

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
            } else if isPastingList {
                // No ScrollView here: the pane's text editor does its own
                // scrolling, and nesting the two makes both behave badly.
                WatchlistPane(trackedBoards: trackedBoards, onAdd: onSave)
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
        // Sized for the roomiest mode (a checked watchlist) so switching tabs
        // never resizes the sheet under the pointer.
        .frame(minWidth: 560, idealWidth: 640, minHeight: 480, idealHeight: 600)
        .onAppear(perform: prime)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(isEditing ? "Edit Tracked Board" : "Track Job Boards")
                .font(.headline)
            Text(headerDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private var headerDetail: String {
        if isEditing { return "Adjust the keyword filters for this board." }
        switch mode {
        case .url: return "Paste any ATS board or job URL and the platform is detected for you."
        case .company: return "Large employers that run their own career site, ready to track in one click."
        case .watchlist: return "Paste a whole watchlist to see which companies are already trackable, and add them in bulk."
        }
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
        let isTracked = trackedBoardKeys.contains(company.trackingKey)
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
            BoardFilterFields(titleKeywords: $titleKeywords,
                              excludeKeywords: $excludeKeywords,
                              locationKeywords: $locationKeywords)
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline.weight(.medium))
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private var footer: some View {
        HStack {
            Button(isPastingList ? "Close" : "Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            // Nothing is staged to commit while browsing the company list, and
            // the watchlist adds inline as you go rather than on the way out.
            if !isBrowsingCompanies && !isPastingList {
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
            detectError = BoardDetectionHint.hint(for: url)
                ?? "That URL isn't a recognized job board. Supported: Greenhouse, Lever, Ashby, Workday, SmartRecruiters, Workable, Recruitee, Personio, BambooHR, Breezy, JazzHR, Teamtailor, Eightfold AI, Avature, iCIMS, Cornerstone OnDemand, Phenom — plus major employers' own career sites."
            return
        }
        detected = board
        if companyName.trimmed.isEmpty { companyName = board.companyName }
    }

    private func save() {
        guard var board = existing ?? detected else { return }
        board.companyName = companyName.trimmed.isEmpty ? board.slug : companyName.trimmed
        board.applyFilters(titleKeywords: titleKeywords,
                           excludeKeywords: excludeKeywords,
                           locationKeywords: locationKeywords)
        onSave([board])
        dismiss()
    }
}
