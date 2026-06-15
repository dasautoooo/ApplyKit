//
//  Debouncer.swift
//  ApplyKit
//

import Foundation

/// Coalesces rapid calls (e.g. per-keystroke autosaves) into a single deferred
/// action that fires once the caller goes quiet for `seconds`. Each `schedule`
/// cancels the previously pending action.
@MainActor
final class Debouncer {
    private var task: Task<Void, Never>?

    /// Run `action` after `seconds` of quiet, cancelling any previously scheduled run.
    func schedule(after seconds: Double = 0.4, _ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    /// Cancel any pending run and execute `action` immediately (e.g. on disappear).
    func flush(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = nil
        action()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
