//
//  RoundTypeOutcomeChart.swift
//  ApplyKit
//

import Charts
import SwiftUI

/// Which kinds of step get passed and which ones end processes: one bar per interview type,
/// split by how the steps that have happened went.
struct RoundTypeOutcomeChart: View {
    let interviews: InterviewInsights
    @State private var hoveredType: String?

    private static let gutter: CGFloat = 112

    private struct Segment: Identifiable {
        let typeLabel: String
        let outcome: InterviewInsights.StepOutcome
        let count: Int
        var id: String { "\(typeLabel)-\(outcome.rawValue)" }
    }

    private var segments: [Segment] {
        interviews.typeSummaries.flatMap { summary in
            InterviewInsights.StepOutcome.allCases.compactMap { outcome in
                let count = summary.count(outcome)
                return count > 0 ? Segment(typeLabel: summary.typeLabel, outcome: outcome, count: count) : nil
            }
        }
    }

    private var labels: [String] { interviews.typeSummaries.map(\.typeLabel) }

    var body: some View {
        if interviews.typeSummaries.isEmpty {
            InsightsEmptyChart(message: "No interviews have happened in this range yet.",
                               height: InsightsLayout.gridChartHeight)
        } else {
            chart
        }
    }

    private var chart: some View {
        let segments = segments
        return Chart {
            ForEach(segments) { segment in
                BarMark(
                    x: .value("Steps", segment.count),
                    y: .value("Type", segment.typeLabel),
                    height: .ratio(0.7)
                )
                .foregroundStyle(by: .value("Outcome", segment.outcome.label))
                .cornerRadius(3)
                .opacity(hoveredType == nil || hoveredType == segment.typeLabel ? 1 : 0.4)
                .annotation(position: .trailing, alignment: .leading, spacing: 6) {
                    if segments.last(where: { $0.typeLabel == segment.typeLabel })?.id == segment.id,
                       let summary = interviews.typeSummaries.first(where: { $0.typeLabel == segment.typeLabel }) {
                        Text("\(summary.passed)/\(summary.steps.count)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                }
            }
            InsightsCategoryLabels(labels: labels, gutter: Self.gutter)
        }
        .chartYScale(domain: labels)
        // Headroom so the count after the longest bar isn't clipped.
        .chartXScale(domain: 0...Double(interviews.typeSummaries.map(\.steps.count).max() ?? 1) * 1.25)
        .chartForegroundStyleScale(domain: InterviewInsights.StepOutcome.styleDomain,
                                   range: InterviewInsights.StepOutcome.styleRange)
        .insightsCategoryGutter(Self.gutter)
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel()
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .insightsHoverPopover(hovered: $hoveredType, hitTest: { point in
                        type(at: point, proxy: proxy, geometry: geometry)
                    }) { typeLabel in
                        popover(for: typeLabel)
                    }
            }
        }
        .frame(height: InsightsLayout.gridChartHeight)
    }

    /// The row under the pointer, anywhere across it, its label included.
    private func type(at point: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> String? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let plot = geometry[plotFrame]
        guard point.y >= plot.minY, point.y <= plot.maxY else { return nil }
        return proxy.value(atY: point.y - plot.minY, as: String.self)
    }

    @ViewBuilder
    private func popover(for typeLabel: String) -> some View {
        if let summary = interviews.typeSummaries.first(where: { $0.typeLabel == typeLabel }) {
            InsightsPopoverList(title: typeLabel, detail: detail(for: summary)) {
                ForEach(summary.steps.reversed()) { step in
                    InsightsPopoverRow(
                        primary: step.companyName,
                        secondary: step.title,
                        trailing: step.outcome?.label,
                        trailingColor: step.outcome?.color ?? .secondary
                    )
                }
            }
        }
    }

    private func detail(for summary: InterviewInsights.TypeSummary) -> String {
        let count = summary.steps.count
        let steps = "\(count) \(count == 1 ? "step" : "steps")"
        guard let rate = summary.passRate else { return "\(steps) · awaiting results" }
        return "\(steps) · \(rate.formatted(.percent.precision(.fractionLength(0)))) passed of \(summary.decided) decided"
    }
}
