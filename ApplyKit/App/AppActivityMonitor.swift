//
//  AppActivityMonitor.swift
//  ApplyKit
//

import SwiftUI

struct ActivityRecord: Identifiable {
    var id: UUID = UUID()
    var timestamp: Date
    var message: String
    var succeeded: Bool
}

@Observable
final class AppActivityMonitor {
    enum ActivityState: Equatable {
        case idle, running, success, failure
    }

    var message: String = ""
    var state: ActivityState = .idle
    var lastMessage: String = ""
    var lastState: ActivityState = .idle
    var history: [ActivityRecord] = []

    var onPersistRecord: ((ActivityRecord) -> Void)?
    var onClearHistory: (() -> Void)?

    /// Work in flight, oldest first. Several operations can run at once — one
    /// per application being tailored — so the bar reports a count rather than
    /// pretending there is a single current task.
    private(set) var running: [(key: String, message: String)] = []

    private var collapseTask: Task<Void, Never>?

    var runningCount: Int { running.count }

    func isRunning(key: String) -> Bool { running.contains { $0.key == key } }

    /// `key` identifies the operation so it can be finished precisely and so the
    /// UI can ask whether one particular thing is busy. Omit it for fire-and-
    /// forget work; finishing then closes the oldest open operation.
    @MainActor
    func start(_ message: String, key: String? = nil) {
        collapseTask?.cancel()
        running.append((key: key ?? UUID().uuidString, message: message))
        self.message = message
        self.state = .running
    }

    @MainActor
    func succeed(_ message: String = "", key: String? = nil) {
        finish(message.isEmpty ? "Done" : message, succeeded: true, key: key)
    }

    @MainActor
    func fail(_ message: String, key: String? = nil) {
        finish(message, succeeded: false, key: key)
    }

    @MainActor
    private func finish(_ message: String, succeeded: Bool, key: String?) {
        collapseTask?.cancel()
        if let key, let index = running.firstIndex(where: { $0.key == key }) {
            running.remove(at: index)
        } else if key == nil, !running.isEmpty {
            running.removeFirst()
        }

        self.lastMessage = message
        self.lastState = succeeded ? .success : .failure
        let record = ActivityRecord(timestamp: Date(), message: message, succeeded: succeeded)
        history.insert(record, at: 0)
        if history.count > 50 { history = Array(history.prefix(50)) }
        onPersistRecord?(record)

        // Anything still running keeps the bar in its running state; the outcome
        // just lands in the history and the last-message line.
        if let current = running.last {
            self.message = current.message
            self.state = .running
        } else {
            self.message = message
            self.state = succeeded ? .success : .failure
            scheduleCollapse()
        }
    }

    @MainActor
    func clearHistory() {
        history.removeAll()
        lastMessage = ""
        lastState = .idle
        if state != .running {
            collapseTask?.cancel()
            message = ""
            state = .idle
        }
        onClearHistory?()
    }

    @MainActor
    private func scheduleCollapse() {
        collapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, state != .running else { return }
            withAnimation(.easeOut(duration: 0.3)) { state = .idle }
        }
    }
}

struct SidebarStatusBar: View {
    let monitor: AppActivityMonitor
    @State private var showingHistory = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 7) {
                statusIcon
                Text(displayMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // A count, not an alert: it sits with the other trailing glyphs
                // and stays in the secondary palette so it doesn't outrank the
                // message it is counting.
                if monitor.runningCount > 1 {
                    Text("\(monitor.runningCount)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5)))
                        .help("\(monitor.runningCount) tasks running")
                }
                if !monitor.history.isEmpty {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.caption2)
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .onTapGesture { showingHistory.toggle() }
            .popover(isPresented: $showingHistory, arrowEdge: .top) {
                historyPopover
            }
        }
        .animation(.easeInOut(duration: 0.2), value: monitor.state)
        .animation(.easeInOut(duration: 0.2), value: monitor.runningCount)
        .animation(.easeInOut(duration: 0.2), value: monitor.message)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch monitor.state {
        case .running:
            ProgressView()
                .controlSize(.small)
                .frame(width: 14, height: 14)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case .idle where monitor.lastState == .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green.opacity(0.45))
                .font(.caption)
        case .idle where monitor.lastState == .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red.opacity(0.45))
                .font(.caption)
        default:
            Image(systemName: "circle.dotted")
                .foregroundStyle(Color(nsColor: .quaternaryLabelColor))
                .font(.caption)
        }
    }

    private var displayMessage: String {
        switch monitor.state {
        case .running, .success, .failure: monitor.message
        case .idle: monitor.lastMessage.isEmpty ? "Ready" : monitor.lastMessage
        }
    }

    private var historyPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Activity")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    monitor.clearHistory()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .disabled(monitor.history.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            // What's in flight, before what has finished — with several
            // applications tailoring at once, this is the part you came for.
            if !monitor.running.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(monitor.running, id: \.key) { operation in
                        HStack(alignment: .top, spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 12, height: 12)
                                .padding(.top, 1)
                            Text(operation.message)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                }
                Divider()
            }

            if monitor.history.isEmpty {
                Text("No activity yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(14)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(monitor.history) { record in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: record.succeeded
                                      ? "checkmark.circle.fill"
                                      : "exclamationmark.triangle.fill")
                                    .foregroundStyle(record.succeeded ? .green : .red)
                                    .font(.caption)
                                    .padding(.top, 1)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.message)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(record.timestamp, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)

                            if record.id != monitor.history.last?.id {
                                Divider().padding(.leading, 36)
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 280)
        .padding(.bottom, 8)
    }
}

// Kept for potential future use (floating pill style)
struct ActivityStatusView: View {
    let monitor: AppActivityMonitor

    var body: some View {
        EmptyView()
    }
}
