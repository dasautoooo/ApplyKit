//
//  StageFunnelChart.swift
//  ApplyKit
//

import Charts
import SwiftUI

/// One horizontal bar per stage, sized by how many applications reached it and split by
/// what happened to them there.
struct StageFunnelChart: View {
    let insights: ApplicationInsights
    @State private var selectedStage: String?
    @Environment(\.isInsightsExport) private var isExport

    var body: some View {
        if insights.reached.isEmpty {
            InsightsEmptyChart(message: "Nothing applied to in this range yet.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                chart
                if !isExport { readout }
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(insights.funnel) { segment in
                BarMark(
                    x: .value("Applications", segment.count),
                    y: .value("Stage", segment.stage.label),
                    height: .ratio(0.7)
                )
                .foregroundStyle(by: .value("Outcome", segment.outcome.label))
                .cornerRadius(3)
                .opacity(selectedStage == nil || selectedStage == segment.stage.label ? 1 : 0.4)
                .annotation(position: .trailing, alignment: .leading, spacing: 6) {
                    if isLastSegment(segment) {
                        totalLabel(for: segment.stage)
                    }
                }
            }
        }
        .chartYScale(domain: insights.reached.map(\.stage.label))
        .chartForegroundStyleScale(domain: FunnelOutcome.styleDomain, range: FunnelOutcome.styleRange)
        .chartYSelection(value: $selectedStage)
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel()
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: CGFloat(insights.reached.count) * 34 + 50)
    }

    /// The total sits after the last segment of each bar, so it lines up with the bar's end.
    private func isLastSegment(_ segment: ApplicationInsights.FunnelSegment) -> Bool {
        insights.funnel.last { $0.stage == segment.stage }?.id == segment.id
    }

    private func totalLabel(for stage: FunnelStage) -> some View {
        HStack(spacing: 4) {
            Text("\(count(at: stage))")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            if let share = shareOfApplied(stage) {
                Text(share.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var readout: some View {
        let stage = insights.reached.first { $0.stage.label == selectedStage }?.stage
        Text(stage.map(description(for:)) ?? "Hover a bar for its breakdown. % is the share of applications that got this far.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }

    private func description(for stage: FunnelStage) -> String {
        let parts = insights.funnel
            .filter { $0.stage == stage }
            .map { "\($0.count) \($0.outcome.label.lowercased())" }
        return "\(stage.label): \(count(at: stage)) reached · " + parts.joined(separator: " · ")
    }

    private func count(at stage: FunnelStage) -> Int {
        insights.reached.first { $0.stage == stage }?.count ?? 0
    }

    /// Against Applied rather than the previous row: Offer can follow any round, so a
    /// step-to-step rate into it would be meaningless (and could top 100%).
    private func shareOfApplied(_ stage: FunnelStage) -> Double? {
        guard stage != .applied, let applied = insights.reached.first?.count, applied > 0 else { return nil }
        return Double(count(at: stage)) / Double(applied)
    }
}
