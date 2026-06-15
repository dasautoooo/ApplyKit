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
    case documents
    case experience
    case tailorExperience
    case jobDescription
    case jdAnalysis
    case gapSuggestions
    case notes

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .roleDetails: "Role Details"
        case .documents: "Documents"
        case .experience: "Experience"
        case .tailorExperience: "Tailor Experience"
        case .jobDescription: "Job Description"
        case .jdAnalysis: "JD Analysis"
        case .gapSuggestions: "Gap Suggestions"
        case .notes: "Notes"
        }
    }

    var icon: String {
        switch self {
        case .roleDetails: "briefcase"
        case .documents: "doc.on.doc"
        case .experience: "checklist"
        case .tailorExperience: "slider.horizontal.3"
        case .jobDescription: "text.alignleft"
        case .jdAnalysis: "brain"
        case .gapSuggestions: "sparkles"
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
    let onSelect: (EditorSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(EditorSection.allCases) { section in
                let isActive = section == model.active
                Button {
                    onSelect(section)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: section.icon)
                            .font(.caption)
                            .frame(width: 16)
                        Text(section.title)
                            .font(.callout.weight(isActive ? .semibold : .regular))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 200, alignment: .topLeading)
        .padding(.horizontal, 10)
    }
}
