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
    /// The segment under the pointer; resting on it opens a popover listing its applications.
    @State private var hoveredSegmentID: String?
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
                .opacity(hoveredSegmentID == nil || hoveredSegmentID == segment.id ? 1 : 0.4)
                .annotation(position: .trailing, alignment: .leading, spacing: 6) {
                    if isLastSegment(segment) {
                        totalLabel(for: segment.stage)
                    }
                }
            }
            InsightsCategoryLabels(labels: stageLabels, gutter: 64)
        }
        .chartYScale(domain: stageLabels)
        // Headroom so the total after the longest bar isn't clipped.
        .chartXScale(domain: 0...xUpperBound)
        .chartForegroundStyleScale(domain: FunnelOutcome.styleDomain, range: FunnelOutcome.styleRange)
        .insightsCategoryGutter(64)
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
                    .insightsHoverPopover(hovered: $hoveredSegmentID, hitTest: { point in
                        segmentID(at: point, proxy: proxy, geometry: geometry)
                    }) { id in
                        if let segment = insights.funnel.first(where: { $0.id == id }) {
                            popover(for: segment)
                        }
                    }
            }
        }
        .frame(height: CGFloat(insights.reached.count) * 34 + 50)
    }

    // MARK: Hover

    /// The piece of a bar under the pointer. Bars stack their segments in `funnel` order, so
    /// the running total along the row says which one the pointer's x falls in.
    private func segmentID(at point: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> String? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let plot = geometry[plotFrame]
        guard plot.contains(point),
              let label = proxy.value(atY: point.y - plot.minY, as: String.self),
              let value = proxy.value(atX: point.x - plot.minX, as: Double.self),
              value >= 0 else { return nil }
        var end = 0.0
        for segment in insights.funnel where segment.stage.label == label {
            end += Double(segment.count)
            if value < end { return segment.id }
        }
        return nil
    }

    private func popover(for segment: ApplicationInsights.FunnelSegment) -> some View {
        // The Applied row's exits can hold most of the search, so they're cut short; from the
        // screen on, every application is listed.
        let isCapped = segment.stage == .applied && segment.outcome != .advanced
        let shown = isCapped ? Array(segment.members.prefix(8)) : segment.members
        let hidden = segment.members.count - shown.count
        let reached = count(at: segment.stage)
        let noun = segment.count == 1 ? "application" : "applications"
        let share = reached > 0
            ? " · \((Double(segment.count) / Double(reached)).formatted(.percent.precision(.fractionLength(0)))) of \(segment.stage.label)"
            : ""
        return InsightsPopoverList(
            title: "\(segment.stage.label) · \(segment.outcome.label)",
            detail: "\(segment.count) \(noun)\(share)",
            footer: hidden > 0 ? "\(hidden) more" : nil
        ) {
            ForEach(shown, id: \.applicationID) { member in
                InsightsPopoverRow(
                    primary: member.companyName.trimmed.isEmpty ? "Untitled" : member.companyName,
                    secondary: member.jobTitle.trimmed.isEmpty ? "No role" : member.jobTitle,
                    trailing: member.isArchived ? "Archived" : nil
                )
            }
        }
    }

    private var xUpperBound: Double {
        Double(insights.reached.map(\.count).max() ?? 1) * 1.2
    }

    private var stageLabels: [String] { insights.reached.map(\.stage.label) }

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
        let stage = insights.funnel.first { $0.id == hoveredSegmentID }?.stage
        Text(stage.map(description(for:)) ?? "Hover a segment to see its applications. % is the share of applications that got this far.")
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
