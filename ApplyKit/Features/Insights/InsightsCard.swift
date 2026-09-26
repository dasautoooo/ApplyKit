//
//  InsightsCard.swift
//  ApplyKit
//

import AppKit
import SwiftUI

/// Chrome shared by every chart on the Insights dashboard.
struct InsightsCard<Content: View>: View {
    let title: String
    var subtitle: String?
    var footnote: String?
    /// Width the card is laid out at when shared; a wide chart gets more room than a grid one.
    var exportWidth: CGFloat = 560
    /// Set on the copy rendered for sharing, which drops the share button.
    var isExport = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if !isExport {
                    InsightsShareMenu(
                        name: title,
                        width: exportWidth,
                        content: AnyView(InsightsCard(title: title, subtitle: subtitle, footnote: footnote,
                                                      exportWidth: exportWidth, isExport: true) { content })
                    )
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .foregroundStyle(.secondary)
                }
            }

            content

            // Cards in a grid row stretch to the tallest; the slack goes here, keeping
            // footnotes on a common baseline.
            Spacer(minLength: 0)

            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        }
    }
}

enum InsightsLayout {
    /// Plot height shared by the charts in the grid, so side-by-side cards line up.
    static let gridChartHeight: CGFloat = 240
}

/// Shown in place of a chart that has nothing to plot yet.
struct InsightsEmptyChart: View {
    let message: String
    var height: CGFloat = 160

    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: height)
    }
}

/// One palette for the whole dashboard, so an outcome keeps its color from chart to chart.
/// System colors, so each adapts to dark mode on its own.
extension FunnelOutcome {
    var color: Color {
        switch self {
        case .advanced: .blue
        case .active: .teal
        case .offer: .green
        case .rejected: .red
        case .ghosted: .gray
        case .withdrawn: .purple
        }
    }

    static var styleDomain: [String] { allCases.map(\.label) }
    static var styleRange: [Color] { allCases.map(\.color) }
}

extension ApplicationInsights.SnapshotCategory {
    /// The open pipeline is one hue deepening with progress; closed outcomes reuse the
    /// funnel's outcome colors.
    var color: Color {
        switch self {
        case .preApply: .blue.opacity(0.25)
        case .applied: .blue.opacity(0.5)
        case .screen: .blue.opacity(0.75)
        case .interviewing: .blue
        case .offer: FunnelOutcome.offer.color
        case .rejected: FunnelOutcome.rejected.color
        case .ghosted: FunnelOutcome.ghosted.color
        case .withdrawn: FunnelOutcome.withdrawn.color
        }
    }
}
