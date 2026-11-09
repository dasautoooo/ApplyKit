//
//  InsightsCard.swift
//  ApplyKit
//

import AppKit
import Charts
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

/// Category names for a chart whose y axis is a list of categories, drawn in a gutter left
/// of the plot and centered on their row. Stands in for the y axis, whose labels on a
/// categorical scale anchor to the row's top edge and run into the marks. Pair with
/// `.insightsCategoryGutter(_:)`, which hides that axis and makes the room.
struct InsightsCategoryLabels<Origin: Plottable, Position: Plottable>: ChartContent {
    /// Each label and the y value its row is centered on: the category itself on a
    /// categorical axis, a number when rows are laid out by hand.
    let rows: [(label: String, position: Position)]
    let gutter: CGFloat
    /// The x value at the plot's leading edge; a date on a time axis.
    let origin: Origin

    private static var spacing: CGFloat { 8 }

    init(rows: [(label: String, position: Position)], gutter: CGFloat, origin: Origin) {
        self.rows = rows
        self.gutter = gutter
        self.origin = origin
    }

    var body: some ChartContent {
        ForEach(rows.indices, id: \.self) { index in
            // An invisible point at the plot's leading edge, just to hang the label on.
            PointMark(x: .value("Origin", origin), y: .value("Category", rows[index].position))
                .symbolSize(0)
                .annotation(position: .leading, alignment: .trailing, spacing: Self.spacing,
                            overflowResolution: .init(x: .disabled, y: .disabled)) {
                    Text(rows[index].label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(width: gutter - Self.spacing, alignment: .trailing)
                }
        }
    }
}

extension InsightsCategoryLabels where Position == String {
    /// For a categorical y axis, where each label is its own row.
    init(labels: [String], gutter: CGFloat, origin: Origin) {
        self.init(rows: labels.map { ($0, $0) }, gutter: gutter, origin: origin)
    }
}

extension InsightsCategoryLabels where Origin == Double, Position == String {
    /// For a categorical y axis over a numeric x axis starting at zero.
    init(labels: [String], gutter: CGFloat) {
        self.init(labels: labels, gutter: gutter, origin: 0)
    }
}

extension View {
    /// Hides the y axis and leaves `width` of room for `InsightsCategoryLabels`.
    func insightsCategoryGutter(_ width: CGFloat) -> some View {
        chartYAxis(.hidden)
            .chartPlotStyle { $0.padding(.leading, width) }
    }
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

extension InterviewInsights.StepOutcome {
    /// Matches the funnel: a pass reads as advancing, a cut as a rejection, a wait as still active.
    var color: Color {
        switch self {
        case .passed: FunnelOutcome.advanced.color
        case .didNotAdvance: FunnelOutcome.rejected.color
        case .pending: FunnelOutcome.active.color
        }
    }

    static var styleDomain: [String] { allCases.map(\.label) }
    static var styleRange: [Color] { allCases.map(\.color) }
}

extension InterviewInsights {
    /// Steps that haven't happened yet, wherever they're drawn.
    static var upcomingColor: Color { .gray }
}

/// Keeps marks along one row from hiding each other: marks closer than `minGap` along the
/// row go into separate lanes, the first on the row's line and the rest alternating above
/// and below it.
enum InsightsLanes {
    /// A lane for each position, in the order given. With `maxLanes` reached, a mark shares the
    /// lane whose last mark is furthest back, where it overlaps least.
    static func assign(_ positions: [Double], minGap: Double, maxLanes: Int = .max) -> [Int] {
        // Left to right; ties keep their given order so the result is stable between redraws.
        let order = positions.indices.sorted { (positions[$0], $0) < (positions[$1], $1) }
        var laneEnds: [Double] = []
        var lanes = Array(repeating: 0, count: positions.count)
        for index in order {
            let position = positions[index]
            let lane: Int
            if let free = laneEnds.firstIndex(where: { position - $0 >= minGap }) {
                lane = free
            } else if laneEnds.count < maxLanes {
                laneEnds.append(position)
                lane = laneEnds.count - 1
            } else {
                lane = laneEnds.indices.min { laneEnds[$0] < laneEnds[$1] } ?? 0
            }
            laneEnds[lane] = position
            lanes[index] = lane
        }
        return lanes
    }

    /// 0 on the line, then one lane above, one below, two above, … in screen points, where
    /// negative is up.
    static func offset(ofLane lane: Int, spacing: Double) -> Double {
        guard lane > 0 else { return 0 }
        let step = Double((lane + 1) / 2) * spacing
        return lane.isMultiple(of: 2) ? step : -step
    }
}
