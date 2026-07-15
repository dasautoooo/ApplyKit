//
//  DetailPanel.swift
//  ApplyKit
//

import SwiftUI

struct DetailPanel<Content: View>: View {
    let title: String
    let trailing: AnyView?
    /// Non-nil makes the panel collapsible, with the collapsed state persisted
    /// in UserDefaults under this key.
    private let collapseKey: String?
    @AppStorage private var isCollapsed: Bool
    @ViewBuilder let content: Content

    init(_ title: String, collapseKey: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = nil
        self.collapseKey = collapseKey
        self._isCollapsed = AppStorage(wrappedValue: false, collapseKey ?? "detailPanel.collapsed._unused")
        self.content = content()
    }

    init<T: View>(_ title: String, collapseKey: String? = nil, @ViewBuilder trailing: () -> T, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = AnyView(trailing())
        self.collapseKey = collapseKey
        self._isCollapsed = AppStorage(wrappedValue: false, collapseKey ?? "detailPanel.collapsed._unused")
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                if collapseKey != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isCollapsed.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                            Text(title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isCollapsed ? "Expand \(title)" : "Collapse \(title)")
                } else {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 8)
                trailing
            }

            if collapseKey == nil || !isCollapsed {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct LabeledControl<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

