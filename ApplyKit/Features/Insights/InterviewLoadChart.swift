//
//  InterviewLoadChart.swift
//  ApplyKit
//

import Charts
import SwiftUI

/// Hours spent in interviews each week, with what's already on the calendar stacked on top,
/// so crunch weeks — past and coming — stand out.
struct InterviewLoadChart: View {
    let interviews: InterviewInsights
    @State private var hoveredWeek: Date?

    private static let heldLabel = "Held"
    private static let upcomingLabel = "Upcoming"

    private struct Bar: Identifiable {
        let week: Date
        let series: String
        let hours: Double
        var id: String { "\(week.timeIntervalSince1970)-\(series)" }
    }

    private var bars: [Bar] {
        interviews.weeks.flatMap { week in
            [Bar(week: week.start, series: Self.heldLabel, hours: week.heldHours),
             Bar(week: week.start, series: Self.upcomingLabel, hours: week.upcomingHours)]
                .filter { $0.hours > 0 }
        }
    }

    var body: some View {
        if interviews.steps.isEmpty {
            InsightsEmptyChart(message: "No interviews logged in this range.",
                               height: InsightsLayout.gridChartHeight)
        } else {
            chart
        }
    }

    private var chart: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(
                    x: .value("Week", bar.week, unit: .weekOfYear),
                    y: .value("Hours", bar.hours)
                )
                .foregroundStyle(by: .value("When", bar.series))
                .cornerRadius(3)
                .opacity(hoveredWeek == nil || hoveredWeek == bar.week ? 1 : 0.4)
            }
        }
        .chartForegroundStyleScale(
            domain: [Self.heldLabel, Self.upcomingLabel],
            range: [FunnelOutcome.advanced.color, FunnelOutcome.advanced.color.opacity(0.35)]
        )
        .chartLegend(position: .bottom, alignment: .leading)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text("\(InterviewInsights.formatHours(hours)) h")
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .insightsHoverPopover(hovered: $hoveredWeek, hitTest: { point in
                        week(at: point, proxy: proxy, geometry: geometry)
                    }) { start in
                        popover(for: start)
                    }
            }
        }
        .frame(height: InsightsLayout.gridChartHeight)
    }

    /// The week under the pointer, when it has interviews to show.
    private func week(at point: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> Date? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let plot = geometry[plotFrame]
        guard plot.contains(point),
              let date = proxy.value(atX: point.x - plot.minX, as: Date.self),
              let start = Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start,
              let week = interviews.weeks.first(where: { $0.start == start }),
              !week.steps.isEmpty else { return nil }
        return week.start
    }

    @ViewBuilder
    private func popover(for start: Date) -> some View {
        if let week = interviews.weeks.first(where: { $0.start == start }) {
            InsightsPopoverList(
                title: "Week of \(start.formatted(.dateTime.month(.abbreviated).day()))",
                detail: detail(for: week)
            ) {
                ForEach(week.steps) { step in
                    InsightsPopoverRow(
                        primary: step.companyName,
                        secondary: step.title,
                        trailing: step.date.formatted(.dateTime.weekday(.abbreviated))
                            + (step.isUpcoming ? " · upcoming" : "")
                    )
                }
            }
        }
    }

    private func detail(for week: InterviewInsights.Week) -> String {
        let count = week.steps.count
        var parts = ["\(count) \(count == 1 ? "interview" : "interviews")",
                     "\(InterviewInsights.formatHours(week.totalHours)) h"]
        if !week.upcoming.isEmpty { parts.append("\(week.upcoming.count) upcoming") }
        return parts.joined(separator: " · ")
    }
}
