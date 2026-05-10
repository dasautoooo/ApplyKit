import SwiftUI

enum ExperienceBadgeStyle { case category, impact, neutral }

struct ExperienceBadge: View {
    let title: String
    let style: ExperienceBadgeStyle

    init(_ title: String, style: ExperienceBadgeStyle) { self.title = title; self.style = style }

    var body: some View {
        Text(title).font(.caption2).fontWeight(.semibold).lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(foreground).background(background)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var foreground: Color {
        switch style {
        case .impact where title == ImpactLevel.high.rawValue: .red
        case .impact where title == ImpactLevel.medium.rawValue: .orange
        case .category: .blue
        default: .secondary
        }
    }
    private var background: Color {
        switch style {
        case .impact where title == ImpactLevel.high.rawValue: .red.opacity(0.12)
        case .impact where title == ImpactLevel.medium.rawValue: .orange.opacity(0.12)
        case .category: .blue.opacity(0.12)
        default: .secondary.opacity(0.12)
        }
    }
}

struct ChipButton: View {
    let title: String; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.caption).fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
    }
}

struct ChipCloud: View {
    let values: [String]; let limit: Int
    var body: some View {
        let visible = Array(values.prefix(limit))
        if !visible.isEmpty {
            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(visible, id: \.self) { value in
                    Text(value).font(.caption2).lineLimit(1)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
}

struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat; var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var currentX: CGFloat = 0; var currentY: CGFloat = 0; var rowHeight: CGFloat = 0; var requiredWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextX = currentX == 0 ? size.width : currentX + horizontalSpacing + size.width
            if nextX > maxWidth, currentX > 0 {
                requiredWidth = max(requiredWidth, currentX); currentX = size.width; currentY += rowHeight + verticalSpacing; rowHeight = size.height
            } else { currentX = nextX; rowHeight = max(rowHeight, size.height) }
        }
        return CGSize(width: proposal.width ?? max(requiredWidth, currentX), height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX; var currentY = bounds.minY; var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextX = currentX == bounds.minX ? currentX + size.width : currentX + horizontalSpacing + size.width
            if nextX > bounds.maxX, currentX > bounds.minX { currentX = bounds.minX; currentY += rowHeight + verticalSpacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(width: size.width, height: size.height))
            currentX += size.width + horizontalSpacing; rowHeight = max(rowHeight, size.height)
        }
    }
}

struct ExperienceSummaryRow: View {
    let experience: ExperienceBullet
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(experience.displayTitle).font(.headline).lineLimit(2)
                Spacer()
                HStack(spacing: 5) {
                    if experience.usableInResume { Image(systemName: "doc.text").help("Usable in resume") }
                    if experience.usableInCoverLetter { Image(systemName: "envelope").help("Usable in cover letter") }
                }.foregroundStyle(.secondary)
            }
            Text([experience.company, experience.role].filter { !$0.trimmed.isEmpty }.joined(separator: " - "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 6) {
                ExperienceBadge(experience.roleCategoryRaw, style: .category)
                ExperienceBadge(experience.impactLevelRaw, style: .impact)
                Spacer(minLength: 0)
            }
            ChipCloud(values: experience.parsedSkills, limit: 5)
        }
        .padding(10).background(.quaternary.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 8)).padding(.vertical, 4)
    }
}

struct ExperienceGroup: Identifiable {
    let title: String; let items: [ExperienceBullet]; var id: String { title }
}

enum ExperienceSourceFilter: String, CaseIterable, Identifiable {
    case all = "All"; case companyExperience = "Company Experience"; case personalProjects = "Personal Projects"
    var id: String { rawValue }
}

enum ExperienceUsageFilter: String, CaseIterable, Identifiable {
    case any = "Any Use"; case resume = "Resume"; case coverLetter = "Cover Letter"; case both = "Resume + Cover Letter"
    var id: String { rawValue }
}

struct DeleteExperienceDialog: View {
    let experience: ExperienceBullet
    @Binding var shouldDeleteSourceFile: Bool
    let onCancel: () -> Void; let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Delete this experience?").font(.headline)
                    Text(experience.displayTitle).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Toggle("Also delete source file", isOn: $shouldDeleteSourceFile)
            Text(shouldDeleteSourceFile
                ? "Removes the experience from the local cache and deletes its YAML file from the workspace, updating experience-bank/index.yml."
                : "Removes the experience from the local cache. The YAML file in the workspace is left untouched.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }.keyboardShortcut(.cancelAction)
                Button("Delete", role: .destructive) { onDelete() }.keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 440)
    }
}
