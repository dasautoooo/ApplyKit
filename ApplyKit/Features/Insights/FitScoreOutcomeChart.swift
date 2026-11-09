//
//  FitScoreOutcomeChart.swift
//  ApplyKit
//

import Charts
import SwiftUI

/// Does the tailor's fit score predict how far an application gets?
struct FitScoreOutcomeChart: View {
    let insights: ApplicationInsights
    /// The chart's width, which decides how close two scores can be before their dots touch.
    /// A typical grid card width until the first layout pass reports the real one.
    @State private var width: CGFloat = 480

    private static let gutter: CGFloat = 64
    private static let endPadding: CGFloat = 12
    /// Centre-to-centre distance at which two dots stop overlapping.
    private static let dotSpacing: CGFloat = 9
    private static let laneSpacing: Double = 8
    /// As many lanes as a stage's row has room for; a row more crowded than that shares lanes.
    private static let maxLanes = 3

    var body: some View {
        if insights.fitPoints.isEmpty {
            InsightsEmptyChart(message: "No applied-to roles have a fit score yet. Run the Resume Tailor's brief to get one.", height: InsightsLayout.gridChartHeight)
        } else {
            let offsets = laneOffsets
            Chart {
                ForEach(insights.fitPoints) { point in
                    PointMark(
                        x: .value("Fit score", point.fitScore),
                        y: .value("Furthest stage", point.stage.label)
                    )
                    .foregroundStyle(by: .value("Outcome", point.outcome.label))
                    .symbolSize(60)
                    // Close scores at the same stage would otherwise sit on one spot.
                    .offset(y: offsets[point.id] ?? 0)
                }
                InsightsCategoryLabels(labels: Self.stageLabels, gutter: Self.gutter)
            }
            // Room past 10 for its tick label, which is dropped when it would overhang the plot.
            .chartXScale(domain: 0...10, range: .plotDimension(endPadding: Self.endPadding))
            .chartYScale(domain: Self.stageLabels)
            .insightsCategoryGutter(Self.gutter)
            // A point is where an application ended up, so "Advanced" never applies here.
            .chartForegroundStyleScale(
                domain: Self.outcomes.map(\.label),
                range: Self.outcomes.map(\.color)
            )
            .chartLegend(position: .bottom, alignment: .leading)
            .chartXAxis {
                AxisMarks(values: .stride(by: 2)) { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel()
                }
            }
            .frame(height: InsightsLayout.gridChartHeight)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }
    }

    /// How far each dot moves off its stage's line so that close scores at the same stage
    /// stay apart.
    private var laneOffsets: [UUID: CGFloat] {
        let pointsPerScore = max(width - Self.gutter - Self.endPadding, 1) / 10
        let minGap = Double(Self.dotSpacing / pointsPerScore)
        var offsets: [UUID: CGFloat] = [:]
        for points in Dictionary(grouping: insights.fitPoints, by: \.stage).values {
            let lanes = InsightsLanes.assign(points.map(\.fitScore), minGap: minGap, maxLanes: Self.maxLanes)
            for (point, lane) in zip(points, lanes) {
                offsets[point.id] = InsightsLanes.offset(ofLane: lane, spacing: Self.laneSpacing)
            }
        }
        return offsets
    }

    private static let stageLabels = FunnelStage.allCases.reversed().map(\.label)

    private static let outcomes = FunnelOutcome.allCases.filter { $0 != .advanced }

}
