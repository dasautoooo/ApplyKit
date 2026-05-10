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

    private var collapseTask: Task<Void, Never>?

    @MainActor
    func start(_ message: String) {
        collapseTask?.cancel()
        self.message = message
        self.state = .running
    }

    @MainActor
    func succeed(_ message: String = "") {
        collapseTask?.cancel()
        let msg = message.isEmpty ? "Done" : message
        self.message = msg
        self.state = .success
        self.lastMessage = msg
        self.lastState = .success
        let record = ActivityRecord(timestamp: Date(), message: msg, succeeded: true)
        history.insert(record, at: 0)
        if history.count > 50 { history = Array(history.prefix(50)) }
        onPersistRecord?(record)
        scheduleCollapse()
    }

    @MainActor
    func fail(_ message: String) {
        collapseTask?.cancel()
        self.message = message
        self.state = .failure
        self.lastMessage = message
        self.lastState = .failure
        let record = ActivityRecord(timestamp: Date(), message: message, succeeded: false)
        history.insert(record, at: 0)
        if history.count > 50 { history = Array(history.prefix(50)) }
        onPersistRecord?(record)
        scheduleCollapse()
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
