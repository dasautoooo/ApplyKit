//
//  InsightsHoverPopover.swift
//  ApplyKit
//

import SwiftUI

extension View {
    /// Opens a system popover for whatever `hitTest` finds under the pointer, once the pointer
    /// rests there. `hovered` follows every move, for highlights that should react right away.
    /// Off in shared images.
    func insightsHoverPopover<Target: Hashable, PopoverContent: View>(
        hovered: Binding<Target?>,
        hitTest: @escaping (CGPoint) -> Target?,
        @ViewBuilder content: @escaping (Target) -> PopoverContent
    ) -> some View {
        modifier(InsightsHoverPopover(hovered: hovered, hitTest: hitTest, popoverContent: content))
    }
}

private struct InsightsHoverPopover<Target: Hashable, PopoverContent: View>: ViewModifier {
    @Binding var hovered: Target?
    let hitTest: (CGPoint) -> Target?
    let popoverContent: (Target) -> PopoverContent

    @State private var shown: Shown?
    @State private var restTask: Task<Void, Never>?
    @Environment(\.isInsightsExport) private var isExport

    /// How long the pointer has to rest before the popover opens, like a help tag: sweeping
    /// across a chart shouldn't open and close a popover per mark.
    private static var restDelay: Duration { .milliseconds(150) }

    private struct Shown: Identifiable {
        let id = UUID()
        let target: Target
        /// Where the pointer came to rest, in the modified view's coordinates.
        let anchor: CGRect
    }

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): pointerMoved(to: point)
                case .ended: pointerLeft()
                }
            }
            .popover(item: $shown,
                     attachmentAnchor: .rect(.rect(shown?.anchor ?? .zero)),
                     arrowEdge: .bottom) { shown in
                popoverContent(shown.target)
            }
            .onDisappear { restTask?.cancel() }
    }

    /// Moving onto something else closes the popover; resting on a target opens one pointing
    /// at where the pointer stopped. It opens below that point, never under the pointer, so
    /// it can't cover what it describes and flicker.
    private func pointerMoved(to point: CGPoint) {
        guard !isExport else { return }
        let target = hitTest(point)
        if target != hovered {
            hovered = target
            shown = nil
        }
        restTask?.cancel()
        guard let target, shown == nil else { return }
        restTask = Task {
            try? await Task.sleep(for: Self.restDelay)
            guard !Task.isCancelled, hovered == target else { return }
            shown = Shown(target: target, anchor: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
        }
    }

    private func pointerLeft() {
        restTask?.cancel()
        hovered = nil
        shown = nil
    }
}

// MARK: - Popover content

/// The layout every Insights popover shares, after a standard macOS popover: a headline and
/// a summary line over a divider, then the details.
struct InsightsPopoverList<Rows: View>: View {
    let title: String
    let detail: String
    /// A closing line under the rows, such as how many were left out.
    var footer: String?
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 8) {
                rows
                if let footer {
                    Text(footer)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .frame(width: 280, alignment: .leading)
    }
}

/// A two-line row: the name over a smaller secondary line, with an optional note on the right.
struct InsightsPopoverRow: View {
    let primary: String
    let secondary: String
    var trailing: String?
    var trailingColor: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(primary)
                Text(secondary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(trailingColor)
            }
        }
    }
}

/// Label–value pairs in two aligned columns, like an inspector.
struct InsightsPopoverFields: View {
    let fields: [(label: String, value: String)]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
            ForEach(fields.indices, id: \.self) { index in
                GridRow {
                    Text(fields[index].label)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text(fields[index].value)
                        .lineLimit(2)
                }
            }
        }
    }
}
