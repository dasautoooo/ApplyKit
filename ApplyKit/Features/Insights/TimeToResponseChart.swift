//
//  TimeToResponseChart.swift
//  ApplyKit
//

import Charts
import SwiftUI

/// Typical wait at each step: the bar spans the middle half of observed waits, the dot is
/// the median.
struct TimeToResponseChart: View {
    let insights: ApplicationInsights

    var body: some View {
        if insights.durations.isEmpty {
            InsightsEmptyChart(message: "Not enough dated history yet. Waits appear once responses and rounds are logged.", height: InsightsLayout.gridChartHeight)
        } else {
            Chart(insights.durations) { summary in
                RuleMark(
                    xStart: .value("25th percentile", summary.p25),
                    xEnd: .value("75th percentile", summary.p75),
                    y: .value("Step", summary.label)
                )
                .lineStyle(StrokeStyle(lineWidth: 8, lineCap: .round))
                .foregroundStyle(FunnelOutcome.advanced.color.opacity(0.3))
                // On the bar rather than the dot, so the label clears the whole range.
                .annotation(position: .trailing, spacing: 10) {
                    Text("median \(Self.days(summary.median)) · n=\(summary.sampleCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                PointMark(
                    x: .value("Median days", summary.median),
                    y: .value("Step", summary.label)
                )
                .symbolSize(70)
                .foregroundStyle(FunnelOutcome.advanced.color)
            }
            .chartYScale(domain: insights.durations.map(\.label))
            // Headroom so the trailing label of the longest wait isn't clipped.
            .chartXScale(domain: 0...xUpperBound)
            .chartXAxisLabel("Days")
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel()
                }
            }
            .frame(height: InsightsLayout.gridChartHeight)
        }
    }

    private var xUpperBound: Double {
        (insights.durations.map(\.p75).max() ?? 1) * 1.45 + 1
    }

    private static func days(_ value: Double) -> String {
        value < 1 ? "<1 d" : "\(Int(value.rounded())) d"
    }
}
