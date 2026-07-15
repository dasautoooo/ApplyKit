//
//  ApplicationEditorNavigation.swift
//  ApplyKit
//

import SwiftUI

/// Holds the editor's scroll-tracking state. Kept in an `@Observable` model (rather than `@State`
/// on the editor) so updating the highlighted section while scrolling re-renders only the rail —
/// not the heavy editor content, which never reads `active`.
@Observable final class EditorScrollModel {
    var active: EditorSection = .roleDetails
    /// Suppresses scroll-position tracking while a rail click animates, so the programmatic
    /// scroll isn't perturbed by `onPreferenceChange` firing mid-animation.
    var isAutoScrolling = false
}

/// Sections of the application editor, in display order, used by the navigation side rail.
enum EditorSection: Int, CaseIterable, Identifiable {
    case roleDetails
    case masterResume
    case documents
    case sectionOrder
    case summary
    case experience
    case tailorExperience
    case skills
    case notes

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .roleDetails: "Role Details"
        case .masterResume: "Master Resume"
        case .documents: "Documents"
        case .sectionOrder: "Section Order"
        case .summary: "Summary"
        case .experience: "Experience"
        case .tailorExperience: "Tailor Experience"
        case .skills: "Skills"
        case .notes: "Notes"
        }
    }

    var icon: String {
        switch self {
        case .roleDetails: "briefcase"
        case .masterResume: "doc.on.doc"
        case .documents: "doc.text"
        case .sectionOrder: "arrow.up.arrow.down"
        case .summary: "text.quote"
        case .experience: "checklist"
        case .tailorExperience: "slider.horizontal.3"
        case .skills: "wrench.and.screwdriver"
        case .notes: "note.text"
        }
    }
}

/// Reports each section's vertical offset (in the scroll viewport's coordinate space) so the
/// rail can highlight whichever section is currently at the top.
struct SectionOffsetKey: PreferenceKey {
    static var defaultValue: [EditorSection: CGFloat] = [:]
    static func reduce(value: inout [EditorSection: CGFloat], nextValue: () -> [EditorSection: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct SectionAnchor: ViewModifier {
    let section: EditorSection
    let space: String

    func body(content: Content) -> some View {
        content
            .id(section)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: SectionOffsetKey.self,
                        value: [section: geo.frame(in: .named(space)).minY]
                    )
                }
            )
    }
}

extension View {
    /// Tags a section so the rail can scroll to it (`.id`) and track its position (offset preference).
    func editorSection(_ section: EditorSection, space: String) -> some View {
        modifier(SectionAnchor(section: section, space: space))
    }
}

/// Always-visible table of contents for the application editor.
struct EditorSectionRail: View {
    let model: EditorScrollModel
    let isInspectorVisible: Bool
    let onToggleInspector: () -> Void
    let onSelect: (EditorSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(EditorSection.allCases) { section in
                let isActive = section == model.active
                Button {
                    onSelect(section)
                } label: {
                    railRowLabel(
                        title: section.title,
                        icon: section.icon,
                        isHighlighted: isActive
                    )
                }
                .buttonStyle(.plain)
            }

            Divider()
                .padding(.vertical, 6)

            Button(action: onToggleInspector) {
                railRowLabel(
                    title: "Job Context",
                    icon: "text.alignleft",
                    isHighlighted: isInspectorVisible
                )
            }
            .buttonStyle(.plain)
            .help(isInspectorVisible ? "Hide the Job Context inspector" : "Show the Job Context inspector")
        }
        .frame(width: 200, alignment: .topLeading)
        .padding(.horizontal, 10)
    }

    private func railRowLabel(title: String, icon: String, isHighlighted: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .frame(width: 16)
            Text(title)
                .font(.callout.weight(isHighlighted ? .semibold : .regular))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isHighlighted ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHighlighted ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }
}
