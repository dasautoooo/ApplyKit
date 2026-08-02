//
//  SelectableList.swift
//  ApplyKit
//
//  Shared chrome for the workspace sidebars. `List(selection:)` insists on
//  painting its own edge-to-edge, saturated selection bar; these rows instead
//  get a soft accent tint when selected and a fainter wash on hover, with text
//  keeping its normal colors.
//
//  The tradeoff is that a plain ScrollView has no built-in keyboard handling, so
//  arrow-key navigation and the delete key are wired up here to preserve what
//  `List` would otherwise have given us.
//

import SwiftUI

struct SelectableList<Content: View>: View {
    @Binding var selection: UUID?
    /// Flat, ordered ids — the traversal order for up/down arrows. Grouped lists
    /// pass their items flattened.
    let orderedIDs: [UUID]
    /// Invoked on the delete key, standing in for `List`'s `.onDelete`.
    var onDelete: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    content()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .focusable()
            .focusEffectDisabled()
            .onMoveCommand { direction in move(direction, proxy: proxy) }
            .onDeleteCommand { onDelete?() }
        }
    }

    private func move(_ direction: MoveCommandDirection, proxy: ScrollViewProxy) {
        guard !orderedIDs.isEmpty else { return }
        let current = orderedIDs.firstIndex { $0 == selection }
        let target: Int
        switch direction {
        case .up:   target = (current ?? 0) - 1
        case .down: target = current.map { $0 + 1 } ?? 0
        default:    return
        }
        let clamped = max(0, min(orderedIDs.count - 1, target))
        selection = orderedIDs[clamped]
        proxy.scrollTo(orderedIDs[clamped])
    }
}

/// Group heading for a `SelectableList`, replacing `Section`'s header.
struct SelectableListSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Row chrome

private struct SelectableRowModifier: ViewModifier {
    let isSelected: Bool
    let onSelect: (() -> Void)?

    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture { onSelect?() }
            .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        if isSelected {
            shape.fill(Color.accentColor.opacity(0.13))
                .overlay(shape.strokeBorder(Color.accentColor.opacity(0.30), lineWidth: 1))
        } else if isHovered {
            shape.fill(Color.primary.opacity(0.05))
        } else {
            Color.clear
        }
    }
}

extension View {
    /// Quiet selection/hover chrome for rows inside a `SelectableList`.
    func selectableRow(isSelected: Bool, onSelect: (() -> Void)? = nil) -> some View {
        modifier(SelectableRowModifier(isSelected: isSelected, onSelect: onSelect))
    }
}
