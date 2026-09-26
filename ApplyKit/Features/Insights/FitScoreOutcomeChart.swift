//
//  FitScoreOutcomeChart.swift
//  ApplyKit
//

import Charts
import SwiftUI

/// Does the tailor's fit score predict how far an application gets?
struct FitScoreOutcomeChart: View {
    let insights: ApplicationInsights

    var body: some View {
        if insights.fitPoints.isEmpty {
            InsightsEmptyChart(message: "No applied-to roles have a fit score yet. Run the Resume Tailor's brief to get one.", height: InsightsLayout.gridChartHeight)
        } else {
            Chart(insights.fitPoints) { point in
                PointMark(
                    x: .value("Fit score", point.fitScore),
                    y: .value("Furthest stage", point.stage.label)
                )
                .foregroundStyle(by: .value("Outcome", point.outcome.label))
                .symbolSize(60)
                // Identical scores at the same stage would otherwise sit on one spot.
                .offset(y: Self.jitter(point.id))
            }
            .chartXScale(domain: 0...10)
            .chartYScale(domain: FunnelStage.allCases.reversed().map(\.label))
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
        }
    }

    private static let outcomes = FunnelOutcome.allCases.filter { $0 != .advanced }

    /// Stable per application, so points don't hop around between redraws.
    private static func jitter(_ id: UUID) -> CGFloat {
        CGFloat(id.uuid.0) / 255 * 12 - 6
    }
}
