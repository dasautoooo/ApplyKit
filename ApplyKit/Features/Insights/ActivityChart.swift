//
//  ActivityChart.swift
//  ApplyKit
//

import Charts
import SwiftUI

/// Applications sent per week, with the responses that came back each week over them.
struct ActivityChart: View {
    let insights: ApplicationInsights
    @State private var selectedDate: Date?

    private struct Week: Identifiable {
        let start: Date
        var applied = 0
        var responses = 0
        var id: Date { start }
    }

    private static let responseColor = Color.orange

    private var weeks: [Week] {
        let calendar = Calendar.current
        var byStart: [Date: Week] = [:]
        for point in insights.activity {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: point.date)?.start else { continue }
            var week = byStart[start] ?? Week(start: start)
            switch point.kind {
            case .applied: week.applied += 1
            case .response: week.responses += 1
            }
            byStart[start] = week
        }
        // Fill quiet weeks with zeros so the response line doesn't bridge straight over them.
        guard let first = byStart.keys.min(), let last = byStart.keys.max() else { return [] }
        var weeks: [Week] = []
        var start = first
        while start <= last {
            weeks.append(byStart[start] ?? Week(start: start))
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { break }
            start = next
        }
        return weeks
    }

    var body: some View {
        let weeks = weeks
        if weeks.isEmpty {
            InsightsEmptyChart(message: "No applications sent in this range.", height: InsightsLayout.gridChartHeight)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                chart(weeks)
                legend(weeks)
            }
        }
    }

    private func chart(_ weeks: [Week]) -> some View {
        Chart {
            ForEach(weeks) { week in
                BarMark(
                    x: .value("Week", week.start, unit: .weekOfYear),
                    y: .value("Applied", week.applied)
                )
                .foregroundStyle(FunnelOutcome.advanced.color.gradient)
                .cornerRadius(3)
            }
            ForEach(weeks) { week in
                LineMark(
                    x: .value("Week", week.start, unit: .weekOfYear),
                    y: .value("Responses", week.responses)
                )
                .foregroundStyle(Self.responseColor)
                .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(
                    x: .value("Week", week.start, unit: .weekOfYear),
                    y: .value("Responses", week.responses)
                )
                .foregroundStyle(Self.responseColor)
                .symbolSize(30)
            }
            if let week = selectedWeek(weeks) {
                RuleMark(x: .value("Week", week.start, unit: .weekOfYear))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(week)
                    }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel()
            }
        }
        .frame(height: InsightsLayout.gridChartHeight)
    }

    private func selectedWeek(_ weeks: [Week]) -> Week? {
        guard let selectedDate,
              let start = Calendar.current.dateInterval(of: .weekOfYear, for: selectedDate)?.start else { return nil }
        return weeks.first { $0.start == start }
    }

    private func tooltip(_ week: Week) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Week of \(week.start.formatted(.dateTime.month(.abbreviated).day()))")
                .font(.caption.weight(.semibold))
            Text("\(week.applied) applied · \(week.responses) responses")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func legend(_ weeks: [Week]) -> some View {
        HStack(spacing: 14) {
            legendItem("Applied", color: FunnelOutcome.advanced.color, total: weeks.reduce(0) { $0 + $1.applied })
            legendItem("Responses", color: Self.responseColor, total: weeks.reduce(0) { $0 + $1.responses })
        }
        .font(.caption)
    }

    private func legendItem(_ label: String, color: Color, total: Int) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
            Text("\(total)").monospacedDigit()
        }
    }
}
