//
//  WatchlistPane.swift
//  ApplyKit
//
//  "Paste a List" in `AddBoardSheet`: take a whole company watchlist — one
//  `Name` or `Name, https://…` per line — and sort it into what's already
//  tracked, what can be tracked now, and what still needs a careers URL.
//
//  Resolution is pattern-based and, apart from the explicit "Find Boards by
//  Name" step, offline: a URL is run through the same detection the URL tab
//  uses, and a bare name is matched against the tracked boards and the
//  Browse Companies catalog.
//

import AppKit
import SwiftUI

/// Pure bucketing logic, kept apart from the view so it's unit-testable
/// without instantiating SwiftUI.
enum WatchlistChecker {
    struct Row: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var url: String?
        var board: TrackedBoard?
        var bucket: Bucket
        var source: Source = .url
    }

    /// Where a row's board came from. Only `.probe` is inference — a slug that
    /// matches a name is strong evidence but not proof of the right employer,
    /// so those rows say so.
    enum Source {
        /// Detected from a URL the user supplied.
        case url
        /// Matched a tracked board or a Browse Companies entry by name.
        case catalog
        /// Matched a name in the bundled `KnownBoardDirectory`.
        case directory
        /// Found by `BoardSlugProber` asking the ATS APIs.
        case probe
    }

    enum Bucket: String, CaseIterable {
        case tracked = "Already tracked"
        case ready = "Ready to track"
        case unmatched = "Needs a URL or a new provider"
    }

    /// Rows worth probing: named, but with no URL to detect from.
    static func probeTargets(in rows: [Row]) -> [Row] {
        rows.filter { $0.bucket == .unmatched && $0.url == nil }
    }

    /// Folds a probe result back into its row. Pure, so the bucketing stays
    /// testable without the network.
    static func resolving(_ row: Row, with board: TrackedBoard?, trackedKeys: Set<String>) -> Row {
        guard let board else { return row }
        var resolved = row
        var named = board
        named.companyName = row.name
        resolved.board = named
        resolved.source = .probe
        resolved.bucket = trackedKeys.contains(named.trackingKey) ? .tracked : .ready
        return resolved
    }

    /// What a URL typed against a single row resolved to.
    enum URLResolution: Equatable {
        case resolved(Row)
        /// Not a usable http(s) URL at all.
        case invalid
        /// A fine URL, but no provider recognizes it.
        case unrecognized

        var row: Row? { if case .resolved(let row) = self { return row } else { return nil } }
    }

    /// Resolves a URL typed directly against one row, so an unmatched company
    /// can be fixed in place instead of being re-pasted as a whole list.
    /// Same detection as `check`, on one line.
    static func resolving(_ row: Row, url text: String, trackedKeys: Set<String>) -> URLResolution {
        guard let url = try? JobURLNormalizer.validatedURL(from: text) else { return .invalid }
        guard let board = ATSBoardResolver.board(for: url) else { return .unrecognized }
        var resolved = row
        var named = board
        named.companyName = row.name
        resolved.url = text.trimmed
        resolved.board = named
        resolved.source = .url
        resolved.bucket = trackedKeys.contains(named.trackingKey) ? .tracked : .ready
        return .resolved(resolved)
    }

    /// One `Name` or `Name, https://…` per line. Resolves each line, in order,
    /// against the URL given, the boards already tracked, and the Browse
    /// Companies catalog. Never touches the network — a name that survives all
    /// three is `BoardSlugProber`'s job, run separately and on request.
    static func check(_ input: String, trackedBoards: [TrackedBoard]) -> [Row] {
        let trackedKeys = Set(trackedBoards.map(\.trackingKey))
        // A tracked board is found by the name it's filed under *or* its slug:
        // a watchlist line says "Amazon", the board's slug is `amazon`, and
        // either spelling should recognize it.
        var trackedByName: [String: TrackedBoard] = [:]
        for board in trackedBoards {
            for spelling in [board.companyName, board.slug] {
                let key = BuiltInCompanies.nameKey(spelling)
                if !key.isEmpty { trackedByName[key] = board }
            }
        }

        return input.split(separator: "\n").compactMap { line -> Row? in
            let text = String(line).trimmed
            guard !text.isEmpty else { return nil }
            let parts = text.split(separator: ",", maxSplits: 1).map { String($0).trimmed }
            let name = parts[0]
            guard !name.isEmpty else { return nil }
            let urlText = parts.count > 1 ? parts[1] : nil

            // 1. A URL that a provider recognizes is the most specific answer.
            if let urlText, let url = try? JobURLNormalizer.validatedURL(from: urlText),
               let board = ATSBoardResolver.board(for: url) {
                var named = board
                named.companyName = name
                return Row(name: name, url: urlText, board: named,
                           bucket: trackedKeys.contains(board.trackingKey) ? .tracked : .ready,
                           source: .url)
            }

            // 2. Already tracked under this name — including the single-company
            // providers (Amazon, Apple, Google…) that have no URL to detect.
            if let board = trackedByName[BuiltInCompanies.nameKey(name)] {
                return Row(name: name, url: urlText, board: board, bucket: .tracked, source: .catalog)
            }

            // 3. In the Browse Companies catalog, which is exact rather than
            // inferred — the slug and host are recorded, not guessed.
            if let company = BuiltInCompanies.company(named: name) {
                let board = company.makeBoard()
                return Row(name: name, url: urlText, board: board,
                           bucket: trackedKeys.contains(board.trackingKey) ? .tracked : .ready,
                           source: .catalog)
            }

            // 4. In the bundled tenant directory — the only way to reach the
            // host-keyed platforms (Workday, iCIMS, Phenom…) from a name, since
            // no slug guess can produce a tenant host.
            if let board = KnownBoardDirectory.board(named: name) {
                return Row(name: name, url: urlText, board: board,
                           bucket: trackedKeys.contains(board.trackingKey) ? .tracked : .ready,
                           source: .directory)
            }

            return Row(name: name, url: urlText, board: nil, bucket: .unmatched, source: .url)
        }
    }
}

/// The "Paste a List" mode of `AddBoardSheet`: content only, so the sheet
/// around it owns the header, the mode picker, and the footer.
///
/// Three steps, in order — paste the list, review what resolved, then set the
/// filters that every board in the batch is added with. Filters come last on
/// purpose: they're a decision about how much of each board you want, which
/// only makes sense once you know which boards you're getting.
struct WatchlistPane: View {
    var trackedBoards: [TrackedBoard]
    /// Takes every board at once: adding them one at a time would start a
    /// separate poll per board, and this pane exists to add them by the dozen.
    let onAdd: ([TrackedBoard]) -> Void

    @State private var step: Step = .paste
    @State private var input = ""
    @State private var rows: [WatchlistChecker.Row] = []
    @State private var selectedRowIDs: Set<UUID> = []
    @State private var isProbing = false
    @State private var probeProgress = 0
    @State private var probeTotal = 0
    @State private var titleKeywords = ""
    @State private var excludeKeywords = ""
    @State private var locationKeywords = ""
    @State private var addedCount = 0
    @State private var copiedNames = false
    /// URLs typed against individual unresolved rows, keyed by row id.
    @State private var urlDrafts: [UUID: String] = [:]
    @State private var urlErrors: [UUID: String] = [:]
    @State private var expandedURLRows: Set<UUID> = []

    private typealias Bucket = WatchlistChecker.Bucket

    private enum Step: Int, CaseIterable {
        case paste, review, filters, done
        var title: String {
            switch self {
            case .paste: "Paste"
            case .review: "Review"
            case .filters: "Filters"
            case .done: "Done"
            }
        }
    }

    /// How many name-only rows are probed at once. Each row already fans out a
    /// request per provider per slug spelling, so a wide outer loop would put
    /// dozens of connections on one host at once.
    private static let probeBatchSize = 4

    private var trackedKeys: Set<String> { Set(trackedBoards.map(\.trackingKey)) }
    private var readyRows: [WatchlistChecker.Row] { rows.filter { $0.bucket == .ready } }
    private var selectedRows: [WatchlistChecker.Row] { readyRows.filter { selectedRowIDs.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if step != .paste { stepBar; Divider() }
            switch step {
            case .paste: pasteStep
            case .review: reviewStep
            case .filters: filtersStep
            case .done: doneStep
            }
        }
    }

    // MARK: - Step bar

    private var stepBar: some View {
        let steps: [Step] = [.paste, .review, .filters]
        return HStack(spacing: 6) {
            ForEach(steps, id: \.rawValue) { item in
                if item != steps.first {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                Text("\(item.rawValue + 1). \(item.title)")
                    .font(.caption.weight(item == step ? .semibold : .regular))
                    .foregroundStyle(item == step ? AnyShapeStyle(.primary)
                                     : AnyShapeStyle(.secondary.opacity(item.rawValue < step.rawValue ? 1 : 0.5)))
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    // MARK: - 1. Paste

    private var pasteStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("One company per line — a bare name, or \"Name, https://…\" if you have its careers URL.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $input)
                .font(.body.monospaced())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: .separatorColor).opacity(0.4)))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            HStack {
                // Shown before checking, so a truncated paste is obvious.
                Text(lineCount == 0 ? "" : "\(lineCount) compan\(lineCount == 1 ? "y" : "ies")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Check List", action: check)
                    .keyboardShortcut(.defaultAction)
                    .disabled(input.trimmed.isEmpty)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var lineCount: Int {
        input.split(separator: "\n").filter { !String($0).trimmed.isEmpty }.count
    }

    // MARK: - 2. Review

    private var reviewStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(Bucket.allCases, id: \.self) { bucket in
                        let bucketRows = rows.filter { $0.bucket == bucket }
                        if !bucketRows.isEmpty { section(bucket, rows: bucketRows) }
                    }
                }
                .padding(16)
            }
            Divider()
            HStack {
                Button("Start Over") { reset() }
                    .buttonStyle(.link)
                Spacer()
                Text(selectedRows.isEmpty ? "Nothing selected"
                     : "\(selectedRows.count) selected")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Set Filters →") { step = .filters }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedRows.isEmpty)
            }
            .padding(16)
        }
    }

    private func section(_ bucket: Bucket, rows bucketRows: [WatchlistChecker.Row]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(bucket.rawValue).font(.subheadline.weight(.semibold))
                Text("\(bucketRows.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if bucket == .ready {
                    let allOn = bucketRows.allSatisfy { selectedRowIDs.contains($0.id) }
                    Button(allOn ? "Select None" : "Select All") {
                        if allOn { selectedRowIDs.subtract(bucketRows.map(\.id)) }
                        else { selectedRowIDs.formUnion(bucketRows.map(\.id)) }
                    }
                    .buttonStyle(.link)
                }
                if bucket == .unmatched {
                    Button(copiedNames ? "Copied" : "Copy Names") { copyNames(of: bucketRows) }
                        .buttonStyle(.link)
                        .disabled(copiedNames)
                    probeControl
                }
            }
            if bucket == .unmatched, !isProbing {
                Text("Names without a URL can be looked up by slug on Greenhouse, Lever, Ashby, and SmartRecruiters. Nothing is guessed — a board only counts when it answers with real postings.\n\nFor the rest, copy the names out, add a careers URL to each as \"Name, https://…\", and check the edited list again.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 2) {
                ForEach(bucketRows) { row in rowView(row) }
            }
        }
    }

    @ViewBuilder
    private var probeControl: some View {
        if isProbing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("\(probeProgress) of \(probeTotal)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        } else {
            let targets = WatchlistChecker.probeTargets(in: rows).count
            if targets > 0 {
                Button("Find Boards by Name (\(targets))") {
                    Task { await findBoardsByName() }
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    private func rowView(_ row: WatchlistChecker.Row) -> some View {
        HStack(spacing: 10) {
            if row.bucket == .ready {
                Toggle("", isOn: Binding(
                    get: { selectedRowIDs.contains(row.id) },
                    set: { on in
                        if on { selectedRowIDs.insert(row.id) } else { selectedRowIDs.remove(row.id) }
                    }
                ))
                .labelsHidden()
            } else if row.bucket == .tracked {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(row.name).font(.body)
                    Spacer(minLength: 8)
                    // Folded by default: a list this long is unreadable with a
                    // text field on every line, and most rows never need one.
                    if row.board == nil {
                        Button(isEditingURL(row) ? "Cancel" : "Add URL") { toggleURLEditor(row) }
                            .buttonStyle(.link).font(.caption)
                    }
                }
                if let board = row.board {
                    Text(detail(for: row, board: board))
                        .font(.caption).foregroundStyle(.secondary)
                } else if isEditingURL(row) {
                    urlEntry(for: row)
                } else {
                    Text(row.url == nil ? "No URL given" : "The URL on this line isn't a recognized job board.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func isEditingURL(_ row: WatchlistChecker.Row) -> Bool {
        expandedURLRows.contains(row.id)
    }

    private func toggleURLEditor(_ row: WatchlistChecker.Row) {
        if expandedURLRows.contains(row.id) {
            expandedURLRows.remove(row.id)
            urlErrors[row.id] = nil
        } else {
            expandedURLRows.insert(row.id)
        }
    }

    /// Fix one company in place: paste its careers or job URL here and the row
    /// re-resolves through the same detection the URL tab uses. Beats copying
    /// the whole list out to add one link.
    private func urlEntry(for row: WatchlistChecker.Row) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                TextField("Paste a careers or job URL", text: urlDraft(for: row))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .font(.caption)
                    .onSubmit { applyURL(to: row) }
                Button("Use") { applyURL(to: row) }
                    .controlSize(.small)
                    .disabled(urlDraft(for: row).wrappedValue.trimmed.isEmpty)
            }
            if let error = urlErrors[row.id] {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    /// Single-company providers have no meaningful slug (Amazon's is "amazon"),
    /// so repeating it would be noise; a probed slug is the one thing worth
    /// checking, so it's always shown and always labelled.
    private func detail(for row: WatchlistChecker.Row, board: TrackedBoard) -> String {
        switch row.source {
        case .probe: "\(board.providerName) · \(board.slug) · matched by name"
        case .directory: "\(board.providerName) · \(board.site ?? board.slug) · from the tenant directory"
        case .catalog where board.slug == board.kindRaw: board.providerName
        case .catalog: "\(board.providerName) · \(board.slug)"
        case .url: "\(board.providerName) · \(board.slug)"
        }
    }

    // MARK: - 3. Filters

    private var filtersStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Applied to all \(selectedRows.count) board\(selectedRows.count == 1 ? "" : "s") you're about to add. Each board's filters can still be changed afterwards from its card.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    BoardFilterFields(titleKeywords: $titleKeywords,
                                      excludeKeywords: $excludeKeywords,
                                      locationKeywords: $locationKeywords)
                    if titleKeywords.trimmed.isEmpty && locationKeywords.trimmed.isEmpty && selectedRows.count > 5 {
                        Label("With no filters, every posting from all \(selectedRows.count) boards lands in the inbox — a single global employer can list a thousand roles.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    DisclosureGroup("Boards to add (\(selectedRows.count))") {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(selectedRows) { row in
                                Text("\(row.name) — \(row.board?.providerName ?? "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                    }
                    .font(.subheadline)
                }
                .padding(16)
            }
            Divider()
            HStack {
                Button("← Back") { step = .review }
                    .buttonStyle(.link)
                Spacer()
                Button("Add \(selectedRows.count) Board\(selectedRows.count == 1 ? "" : "s")", action: addSelected)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedRows.isEmpty)
            }
            .padding(16)
        }
    }

    // MARK: - 4. Done

    private var doneStep: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40)).foregroundStyle(.green)
            Text("Added \(addedCount) board\(addedCount == 1 ? "" : "s")")
                .font(.title3.weight(.semibold))
            Text("They're being checked for postings now — results land in the inbox behind this sheet.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Check Another List") { reset() }
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Actions

    private func check() {
        rows = WatchlistChecker.check(input, trackedBoards: trackedBoards)
        // Everything trackable is selected by default: the review step is for
        // taking things out, not for opting each one in.
        selectedRowIDs = Set(rows.filter { $0.bucket == .ready }.map(\.id))
        step = .review
    }

    private func urlDraft(for row: WatchlistChecker.Row) -> Binding<String> {
        Binding(get: { urlDrafts[row.id] ?? "" },
                set: { urlDrafts[row.id] = $0; urlErrors[row.id] = nil })
    }

    private func applyURL(to row: WatchlistChecker.Row) {
        let text = (urlDrafts[row.id] ?? "").trimmed
        guard !text.isEmpty, let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        switch WatchlistChecker.resolving(row, url: text, trackedKeys: trackedKeys) {
        case .resolved(let updated):
            rows[index] = updated
            urlDrafts[row.id] = nil
            urlErrors[row.id] = nil
            expandedURLRows.remove(row.id)
            // Matches what `check` and the probe do: anything newly trackable
            // joins the selection, and the review step is for taking things out.
            if updated.bucket == .ready { selectedRowIDs.insert(row.id) }
        case .invalid:
            urlErrors[row.id] = "Enter a complete URL, including https://."
        case .unrecognized:
            urlErrors[row.id] = (try? JobURLNormalizer.validatedURL(from: text))
                .flatMap(BoardDetectionHint.hint(for:))
                ?? "No provider recognizes that URL. Open a job on the company's careers site and paste that link."
        }
    }

    /// Copies the unresolved names one per line — the same shape the paste box
    /// takes — so they can be pasted out, given a careers URL each, and checked
    /// again as `Name, https://…`.
    private func copyNames(of rows: [WatchlistChecker.Row]) {
        let names = rows.map(\.name).joined(separator: "\n")
        guard !names.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(names, forType: .string)
        copiedNames = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copiedNames = false
        }
    }

    private func reset() {
        input = ""
        rows = []
        selectedRowIDs = []
        addedCount = 0
        step = .paste
    }

    private func addSelected() {
        let boards = selectedRows.compactMap { row -> TrackedBoard? in
            guard var board = row.board else { return nil }
            board.applyFilters(titleKeywords: titleKeywords,
                               excludeKeywords: excludeKeywords,
                               locationKeywords: locationKeywords)
            return board
        }
        guard !boards.isEmpty else { return }
        addedCount = boards.count
        onAdd(boards)
        step = .done
    }

    /// Look up the name-only rows against the slug-addressable ATS APIs, in
    /// small batches so a 200-company paste doesn't open hundreds of
    /// connections at once. Rows update as each batch lands.
    private func findBoardsByName() async {
        let targets = WatchlistChecker.probeTargets(in: rows)
        guard !targets.isEmpty else { return }
        isProbing = true
        probeProgress = 0
        probeTotal = targets.count
        defer { isProbing = false }

        let keys = trackedKeys
        for batch in stride(from: 0, to: targets.count, by: Self.probeBatchSize) {
            let slice = targets[batch..<min(batch + Self.probeBatchSize, targets.count)]
            let found = await withTaskGroup(of: (UUID, TrackedBoard?).self) { group in
                for row in slice {
                    group.addTask { (row.id, await BoardSlugProber.probe(name: row.name)) }
                }
                var results: [UUID: TrackedBoard] = [:]
                for await (id, board) in group { if let board { results[id] = board } }
                return results
            }
            for (id, board) in found {
                guard let index = rows.firstIndex(where: { $0.id == id }) else { continue }
                rows[index] = WatchlistChecker.resolving(rows[index], with: board, trackedKeys: keys)
                // Newly resolved rows join the selection, matching what `check`
                // does — the review step is for taking things out.
                if rows[index].bucket == .ready { selectedRowIDs.insert(id) }
            }
            probeProgress += slice.count
        }
    }
}
