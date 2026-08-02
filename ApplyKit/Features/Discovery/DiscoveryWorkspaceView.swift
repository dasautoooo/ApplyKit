//
//  DiscoveryWorkspaceView.swift
//  ApplyKit
//
//  The "Discover" section: track company job boards, poll them (AI-free) for new
//  postings, and triage the inbox. Importing a posting reuses the existing AI
//  import path (JobURLImportSheet). See JobDiscoveryService / ATSBoardResolver.
//

import AppKit
import SwiftUI

/// Shared orchestration for a discovery refresh: poll, dedupe, merge into the
/// store, persist, and report. Called from the manual Refresh button and from the
/// on-launch refresh in ContentView.
@MainActor
enum DiscoveryCoordinator {
    static func refresh(store: AppDataStore, settings: AppSettings,
                        monitor: AppActivityMonitor, service: JobDiscoveryService) async {
        // Prune catch-all talent-pool postings that slipped into the inbox before
        // the current filter rules existed.
        let prunedCount = store.discoveredJobs.count
        store.discoveredJobs.removeAll { $0.state == .new && JobDiscoveryService.isCatchAllPosting(title: $0.title) }
        if store.discoveredJobs.count != prunedCount {
            try? WorkspaceSyncService.persistDiscoveredJobs(store.discoveredJobs, settings: settings)
        }

        let boards = store.trackedBoards
        guard !boards.isEmpty else { return }
        monitor.start("Checking \(boards.count) board\(boards.count == 1 ? "" : "s") for new jobs…")
        let appKeys = Set(store.applications.compactMap { JobURLNormalizer.duplicateKey(for: $0.jobURL) })
        let outcome = await service.refresh(boards: boards,
                                            existingApplicationKeys: appKeys,
                                            existingDiscovered: store.discoveredJobs)

        let boardByID = Dictionary(uniqueKeysWithValues: outcome.boards.map { ($0.id, $0) })
        store.trackedBoards = store.trackedBoards.map { boardByID[$0.id] ?? $0 }
        if !outcome.newJobs.isEmpty {
            store.discoveredJobs.insert(contentsOf: outcome.newJobs, at: 0)
        }

        // Postings that vanished from a board that polled cleanly are marked
        // closed rather than deleted, so a role disappearing is visible instead
        // of silently leaving the inbox.
        let closedIDs = JobDiscoveryService.closedJobIDs(in: store.discoveredJobs,
                                                         liveKeysByBoard: outcome.liveKeysByBoard)
        if !closedIDs.isEmpty {
            for index in store.discoveredJobs.indices where closedIDs.contains(store.discoveredJobs[index].id) {
                store.discoveredJobs[index].state = .closed
            }
        }

        try? WorkspaceSyncService.persistTrackedBoards(store.trackedBoards, settings: settings)
        if !outcome.newJobs.isEmpty || !closedIDs.isEmpty {
            try? WorkspaceSyncService.persistDiscoveredJobs(store.discoveredJobs, settings: settings)
        }

        let count = outcome.newJobs.count
        if count == 0, let firstError = outcome.errors.first {
            monitor.fail(outcome.errors.count == 1 ? firstError : "\(outcome.errors.count) boards failed. \(firstError)")
        } else {
            var message = count == 0 ? "No new postings found." : "Found \(count) new posting\(count == 1 ? "" : "s")."
            if !closedIDs.isEmpty {
                message += " \(closedIDs.count) no longer listed."
            }
            monitor.succeed(message)
        }
    }
}

struct DiscoveryWorkspaceView: View {
    @Environment(AppDataStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(AppActivityMonitor.self) private var activityMonitor

    @State private var service = JobDiscoveryService()
    @State private var scraper = JobPageScraper()
    @State private var showAddBoard = false
    @State private var editingBoard: TrackedBoard?
    @State private var importingJob: DiscoveredJob?
    @State private var isRefreshing = false
    @State private var inboxSearch = ""
    @State private var scope: InboxScope = .new
    @State private var selectedJobID: UUID?
    @State private var loadingJobID: UUID?
    @State private var jdError = ""
    @State private var inboxWidth: CGFloat = 380
    @State private var boardFilter: Set<UUID> = []
    @State private var sortOrder: JobSort = .postedNewest

    private enum InboxScope: String, CaseIterable, Identifiable {
        case new = "New", dismissed = "Dismissed", imported = "Imported", closed = "Closed"
        var id: String { rawValue }
        var state: DiscoveryState {
            switch self {
            case .new: .new
            case .dismissed: .dismissed
            case .imported: .imported
            case .closed: .closed
            }
        }
    }

    private enum JobSort: String, CaseIterable, Identifiable {
        case discoveredNewest = "Newest found"
        case postedNewest = "Recently posted"
        case company = "Company"
        case title = "Title"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .discoveredNewest: "sparkles"
            case .postedNewest: "clock"
            case .company: "building.2"
            case .title: "textformat"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            boardsStrip
            Divider()
            inbox
        }
        .toolbar {
            ToolbarItem {
                Button { showAddBoard = true } label: {
                    Label("Track Board", systemImage: "plus")
                }
                .help("Track a job board by URL, or pick a company")
            }
            ToolbarItem {
                Button(action: refresh) {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing || store.trackedBoards.isEmpty)
            }
        }
        .sheet(isPresented: $showAddBoard) {
            AddBoardSheet(existing: nil,
                          trackedProviderIDs: Set(store.trackedBoards.map(\.kindRaw))) { addBoard($0) }
        }
        .sheet(item: $editingBoard) { board in
            AddBoardSheet(existing: board) { updateBoard($0) }
        }
        .sheet(item: $importingJob) { job in
            JobURLImportSheet(
                settings: settings,
                masterResumes: store.masterResumes,
                experiences: store.experiences,
                existingApplications: store.applications,
                initialURL: job.url,
                onCreate: { draft, resume in
                    try createImportedApplication(from: draft, masterResume: resume, discovered: job)
                }
            )
        }
    }

    // MARK: - Boards strip

    private var boardsStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tracked Boards").font(.headline)
                Spacer()
                Text("\(store.trackedBoards.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if store.trackedBoards.isEmpty {
                Text("Track a Greenhouse, Lever, Ashby, or Workday board to discover new roles automatically.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                let counts = newCountsByBoard
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.trackedBoards) { board in
                            boardChip(board, newCount: counts[board.id] ?? 0)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
    }

    private func boardChip(_ board: TrackedBoard, newCount: Int) -> some View {
        let isActive = boardFilter.contains(board.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "building.2.crop.circle")
                    .foregroundStyle(.tint)
                Text(board.displayName).font(.body.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(newCount)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(newCount > 0 ? Color.white : Color.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(newCount > 0 ? Color.accentColor : Color(nsColor: .quaternaryLabelColor),
                                in: Capsule())
                    .help("\(newCount) new posting\(newCount == 1 ? "" : "s")")
            }
            Text(board.providerName).font(.subheadline).foregroundStyle(.secondary)
            Text(board.lastPolledAt.map { "Checked \($0.formatted(.relative(presentation: .named)))" } ?? "Not checked yet")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(width: 210, alignment: .leading)
        .background(isActive ? Color.accentColor.opacity(0.12) : Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(isActive ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isActive ? 1.5 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { toggleBoardFilter(board.id) }
        .help("Click to show only this company")
        .contextMenu {
            Button { editingBoard = board } label: { Label("Edit Filters…", systemImage: "slider.horizontal.3") }
            Button(role: .destructive) { removeBoard(board) } label: { Label("Stop Tracking", systemImage: "trash") }
        }
    }

    // MARK: - Inbox

    private var inbox: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Picker("", selection: $scope) {
                    ForEach(InboxScope.allCases) { s in
                        Text("\(s.rawValue) (\(count(for: s)))").tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search postings", text: $inboxSearch).textFieldStyle(.plain)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor).opacity(0.4)))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Menu {
                    Picker("Sort by", selection: $sortOrder) {
                        ForEach(JobSort.allCases) { order in
                            Label(order.rawValue, systemImage: order.systemImage).tag(order)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 16).padding(.top, 10)

            if !boardFilter.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.tint)
                    Text("Showing \(boardFilter.count) compan\(boardFilter.count == 1 ? "y" : "ies")")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Show all") { boardFilter.removeAll() }
                        .buttonStyle(.plain).font(.caption.weight(.medium)).foregroundStyle(.tint)
                }
                .padding(.horizontal, 16).padding(.top, 6)
            }
            Color.clear.frame(height: 10)

            if filteredJobs.isEmpty {
                ContentUnavailableView(
                    scope == .new ? "No new postings" : "Nothing here",
                    systemImage: "tray",
                    description: Text(store.trackedBoards.isEmpty
                        ? "Track a board, then refresh to discover roles."
                        : "Refresh to check your boards for new postings.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StableSidebarSplit(sidebarWidth: $inboxWidth, minWidth: 320, maxWidth: 520) {
                    SelectableList(selection: $selectedJobID,
                                   orderedIDs: filteredJobs.map(\.id),
                                   onDelete: { if let selectedJob { setState(selectedJob, .dismissed) } }) {
                        ForEach(filteredJobs) { job in
                            DiscoveredJobRow(
                                job: job,
                                isSelected: job.id == selectedJobID,
                                onImport: { importingJob = job },
                                onDismiss: { setState(job, .dismissed) },
                                onRestore: { setState(job, .new) },
                                onOpen: { open(job.url) }
                            )
                            .selectableRow(isSelected: job.id == selectedJobID) {
                                selectedJobID = job.id
                            }
                            .id(job.id)
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                } detail: {
                    postingDetail
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: selectedJobID) { _, _ in
            jdError = ""
            if let job = selectedJob { loadDescriptionIfNeeded(job) }
        }
    }

    // MARK: - Posting detail (cached JD)

    private var selectedJob: DiscoveredJob? {
        guard let selectedJobID else { return nil }
        return store.discoveredJobs.first { $0.id == selectedJobID }
    }

    @ViewBuilder private var postingDetail: some View {
        if let job = selectedJob {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(job.title.isEmpty ? "Untitled Posting" : job.title)
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Label(job.companyName, systemImage: "building.2")
                        if !job.location.isEmpty { Label(job.location, systemImage: "mappin.and.ellipse") }
                        if let posted = job.postedAt {
                            Label(posted.formatted(.relative(presentation: .named)), systemImage: "clock")
                        }
                    }
                    .font(.subheadline).foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button { open(job.url) } label: { Label("Open in Browser", systemImage: "safari") }
                        if job.state == .new {
                            Button { importingJob = job } label: { Label("Import", systemImage: "square.and.arrow.down") }
                                .buttonStyle(.borderedProminent)
                            Button("Dismiss") { setState(job, .dismissed) }
                        } else if job.state == .dismissed {
                            Button("Restore") { setState(job, .new) }
                        } else if job.state == .closed {
                            Label("No longer listed", systemImage: "clock.badge.xmark")
                                .foregroundStyle(.orange)
                            Button("Move back to New") { setState(job, .new) }
                        } else {
                            Label("Imported", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(16)
                Divider()
                descriptionBody(for: job)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ContentUnavailableView("Select a posting", systemImage: "doc.text",
                                   description: Text("Choose a posting to load and read its description."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func descriptionBody(for job: DiscoveredJob) -> some View {
        if loadingJobID == job.id {
            VStack(spacing: 10) {
                ProgressView()
                Text("Loading description…").font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !job.jobDescription.trimmed.isEmpty {
            ScrollView {
                Text(job.jobDescription)
                    .font(.body)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
            }
        } else {
            VStack(spacing: 12) {
                if jdError.isEmpty {
                    Text("No description cached yet.").foregroundStyle(.secondary)
                } else {
                    Label(jdError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                Button { loadDescription(job, force: true) } label: {
                    Label("Load Description", systemImage: "arrow.down.doc")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
    }

    private var filteredJobs: [DiscoveredJob] {
        let query = inboxSearch.trimmed.lowercased()
        return store.discoveredJobs.filter { job in
            job.state == scope.state
                && (boardFilter.isEmpty || boardFilter.contains(job.boardID))
                && (query.isEmpty
                    || job.title.lowercased().contains(query)
                    || job.companyName.lowercased().contains(query)
                    || job.location.lowercased().contains(query))
        }
        .sorted(by: sortComparator)
    }

    private func sortComparator(_ lhs: DiscoveredJob, _ rhs: DiscoveredJob) -> Bool {
        switch sortOrder {
        case .discoveredNewest:
            lhs.discoveredAt > rhs.discoveredAt
        case .postedNewest:
            // Several providers (Google, Tesla, Meta, JazzHR, Teamtailor) never
            // report a posting date. Falling back to when we found the job keeps
            // those near the top with everything else recent, instead of sinking
            // them permanently below every dated posting.
            (lhs.postedAt ?? lhs.discoveredAt) > (rhs.postedAt ?? rhs.discoveredAt)
        case .company:
            lhs.companyName.localizedCaseInsensitiveCompare(rhs.companyName) == .orderedAscending
        case .title:
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func count(for scope: InboxScope) -> Int {
        store.discoveredJobs.filter { $0.state == scope.state }.count
    }

    /// Pending (`new`) postings per board, computed in a single pass so each chip
    /// doesn't rescan the whole discoveries array while rendering.
    private var newCountsByBoard: [UUID: Int] {
        store.discoveredJobs.reduce(into: [:]) { counts, job in
            guard job.state == .new else { return }
            counts[job.boardID, default: 0] += 1
        }
    }


    private func toggleBoardFilter(_ boardID: UUID) {
        if boardFilter.contains(boardID) { boardFilter.remove(boardID) } else { boardFilter.insert(boardID) }
    }

    // MARK: - Actions

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            await DiscoveryCoordinator.refresh(store: store, settings: settings,
                                               monitor: activityMonitor, service: service)
            isRefreshing = false
        }
    }

    private func addBoard(_ board: TrackedBoard) {
        store.trackedBoards.append(board)
        persistBoards()
        refresh()
    }

    private func updateBoard(_ board: TrackedBoard) {
        guard let idx = store.trackedBoards.firstIndex(where: { $0.id == board.id }) else { return }
        store.trackedBoards[idx] = board
        persistBoards()
        // Immediately drop already-surfaced postings that the tightened filters now
        // reject, then refresh to pull in any the loosened filters newly allow.
        reapplyFilters(for: board)
        refresh()
    }

    /// Re-evaluate a board's `new` postings against its current filters, removing
    /// those that no longer pass. Imported/dismissed rows are historical and kept.
    private func reapplyFilters(for board: TrackedBoard) {
        let before = store.discoveredJobs.count
        store.discoveredJobs.removeAll { job in
            guard job.boardID == board.id, job.state == .new else { return false }
            let posting = DiscoveredPosting(externalID: job.externalID, title: job.title,
                                            location: job.location, url: job.url, postedAt: job.postedAt)
            return !JobDiscoveryService.passesFilters(posting, board: board)
        }
        if store.discoveredJobs.count != before {
            if let selectedJobID, !store.discoveredJobs.contains(where: { $0.id == selectedJobID }) {
                self.selectedJobID = nil
            }
            persistJobs()
        }
    }

    private func removeBoard(_ board: TrackedBoard) {
        store.trackedBoards.removeAll { $0.id == board.id }
        boardFilter.remove(board.id)
        // Drop this board's pending and closed discoveries so they don't linger as
        // orphans and don't block re-discovery (URL dedup is global). Imported and
        // dismissed rows are kept — those record a decision you made.
        let before = store.discoveredJobs.count
        store.discoveredJobs.removeAll {
            $0.boardID == board.id && ($0.state == .new || $0.state == .closed)
        }
        if store.discoveredJobs.count != before { persistJobs() }
        if let selectedJobID, !store.discoveredJobs.contains(where: { $0.id == selectedJobID }) {
            self.selectedJobID = nil
        }
        persistBoards()
    }

    private func setState(_ job: DiscoveredJob, _ state: DiscoveryState) {
        guard let idx = store.discoveredJobs.firstIndex(where: { $0.id == job.id }) else { return }
        store.discoveredJobs[idx].state = state
        persistJobs()
    }

    /// Fetch + cache the JD on first open only; a cached posting is left untouched.
    private func loadDescriptionIfNeeded(_ job: DiscoveredJob) {
        guard job.jobDescription.trimmed.isEmpty else { return }
        loadDescription(job, force: false)
    }

    private func loadDescription(_ job: DiscoveredJob, force: Bool) {
        guard loadingJobID != job.id else { return }
        loadingJobID = job.id
        jdError = ""
        Task {
            defer { loadingJobID = nil }
            do {
                let url = try JobURLNormalizer.validatedURL(from: job.url)
                let content = try await scraper.scrape(url: url)
                let text = content.visibleText.trimmed
                guard !text.isEmpty else {
                    jdError = "Couldn't find a description on the posting page."
                    return
                }
                guard let idx = store.discoveredJobs.firstIndex(where: { $0.id == job.id }) else { return }
                store.discoveredJobs[idx].jobDescription = text
                store.discoveredJobs[idx].jobDescriptionFetchedAt = Date()
                persistJobs()
            } catch {
                jdError = error.localizedDescription
            }
        }
    }

    private func createImportedApplication(from draft: JobImportDraft, masterResume: MasterResume,
                                           discovered: DiscoveredJob) throws {
        var application = JobApplication(companyName: draft.companyName.trimmed, jobTitle: draft.jobTitle.trimmed)
        application.jobURL = draft.jobURL.trimmed
        application.location = draft.location.trimmed
        application.workModeRaw = draft.workModeRaw
        application.employmentTypeRaw = draft.employmentTypeRaw
        application.sourceRaw = draft.sourceRaw
        application.deadline = draft.deadline
        application.jobDescription = draft.jobDescription.trimmed
        application.sourceMasterResumeID = masterResume.id
        application.copyResumeContent(from: masterResume)
        try WorkspaceSyncService.persistApplication(application, documents: [], settings: settings)
        store.applications.insert(application, at: 0)

        if let idx = store.discoveredJobs.firstIndex(where: { $0.id == discovered.id }) {
            store.discoveredJobs[idx].state = .imported
            store.discoveredJobs[idx].importedApplicationID = application.id
            persistJobs()
        }
    }

    private func persistBoards() {
        try? WorkspaceSyncService.persistTrackedBoards(store.trackedBoards, settings: settings)
    }

    private func persistJobs() {
        try? WorkspaceSyncService.persistDiscoveredJobs(store.discoveredJobs, settings: settings)
    }

    private func open(_ url: String) {
        if let u = try? JobURLNormalizer.validatedURL(from: url) { NSWorkspace.shared.open(u) }
    }
}

/// A quiet, scannable triage row: actions stay hidden until the row is hovered or
/// selected (and are always available via right-click), so a long list reads as
/// content rather than a wall of repeated buttons.
private struct DiscoveredJobRow: View {
    let job: DiscoveredJob
    let isSelected: Bool
    let onImport: () -> Void
    let onDismiss: () -> Void
    let onRestore: () -> Void
    let onOpen: () -> Void

    @State private var isHovered = false

    private var showActions: Bool { isHovered || isSelected }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(job.title.isEmpty ? "Untitled Posting" : job.title)
                    .font(.body.weight(.medium))
                    .strikethrough(job.state == .closed, color: .secondary)
                    .foregroundStyle(job.state == .closed ? .secondary : .primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(metadataLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            accessory
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: showActions)
        .contextMenu {
            switch job.state {
            case .new:
                Button("Import…", action: onImport)
                Button("Dismiss", action: onDismiss)
            case .dismissed:
                Button("Restore", action: onRestore)
            case .closed:
                Button("Move Back to New", action: onRestore)
            case .imported:
                EmptyView()
            }
            Divider()
            Button("Open in Browser", action: onOpen)
        }
    }


    private var metadataLine: String {
        var parts = [job.companyName]
        if !job.location.isEmpty { parts.append(job.location) }
        if let posted = job.postedAt {
            parts.append(posted.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }

    /// Kept in the layout at all times (fading via opacity) so revealing the
    /// actions never reflows the row's text.
    @ViewBuilder private var accessory: some View {
        switch job.state {
        case .new:
            HStack(spacing: 1) {
                iconButton("safari", "Open in browser", action: onOpen)
                iconButton("xmark", "Dismiss", action: onDismiss)
                iconButton("square.and.arrow.down", "Import", action: onImport)
            }
            .opacity(showActions ? 1 : 0)
            .allowsHitTesting(showActions)
        case .dismissed:
            iconButton("arrow.uturn.backward", "Restore", action: onRestore)
                .opacity(showActions ? 1 : 0.35)
                .allowsHitTesting(showActions)
        case .imported:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Imported")
        case .closed:
            HStack(spacing: 1) {
                if showActions {
                    iconButton("safari", "Open in browser", action: onOpen)
                    iconButton("arrow.uturn.backward", "Move back to New", action: onRestore)
                }
                Image(systemName: "clock.badge.xmark")
                    .foregroundStyle(.orange)
                    .help("No longer listed on the board")
            }
        }
    }

    private func iconButton(_ symbol: String, _ help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
