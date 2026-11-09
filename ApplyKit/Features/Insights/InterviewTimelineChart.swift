//
//  InterviewTimelineChart.swift
//  ApplyKit
//

import Charts
import SwiftUI

/// Each company's interview process on one shared calendar: a line from its first step to its
/// latest, a dot per step colored by how it went, hollow for steps still to come, a star
/// where it ended in an offer and a cross where it ended in a rejection.
struct InterviewTimelineChart: View {
    let interviews: InterviewInsights
    @State private var hoveredMarkerID: String?
    /// The chart's width, which decides how close in time two steps can be before their dots
    /// would touch. A typical card width until the first layout pass reports the real one.
    @State private var width: CGFloat = 900

    private static let gutter: CGFloat = 140
    /// Room above the plot for the Today label and below it for the date axis.
    private static let chrome: CGFloat = 44
    /// How close the pointer has to be to a dot to pick it.
    private static let hitRadius: CGFloat = 8

    var body: some View {
        if interviews.processes.isEmpty {
            InsightsEmptyChart(message: "No interviews logged in this range.")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                chart(InterviewTimelineLayout(processes: interviews.processes, domain: xDomain,
                                              plotWidth: width - Self.gutter))
                legend
            }
        }
    }

    private func chart(_ layout: InterviewTimelineLayout) -> some View {
        // y counts points up from the plot's bottom, so the layout's top-down rows flip.
        let height = layout.height
        return Chart {
            ForEach(layout.rows, id: \.process.id) { row in
                RuleMark(
                    xStart: .value("First step", row.process.first),
                    xEnd: .value("Latest step", row.process.last),
                    y: .value("Row", height - row.center)
                )
                .foregroundStyle(Color.secondary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }

            ForEach(layout.dots, id: \.id) { dot in
                PointMark(
                    x: .value("Date", dot.marker.date),
                    y: .value("Row", height - dot.y)
                )
                .symbol { symbol(for: dot) }
            }

            RuleMark(x: .value("Today", interviews.now))
                .foregroundStyle(Color.secondary.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .center, spacing: 2,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    Text("Today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

            InsightsCategoryLabels(rows: layout.rows.map { ($0.process.label, height - $0.center) },
                                   gutter: Self.gutter, origin: xDomain.lowerBound)
        }
        .chartYScale(domain: 0...height)
        .chartXScale(domain: xDomain)
        .chartYAxis(.hidden)
        // A plot exactly as tall as the layout, so its offsets land in points.
        .chartPlotStyle { $0.frame(height: height).padding(.leading, Self.gutter) }
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
                    .insightsHoverPopover(hovered: $hoveredMarkerID, hitTest: { point in
                        marker(near: point, in: layout, proxy: proxy, geometry: geometry)
                    }) { id in
                        if let dot = layout.dots.first(where: { $0.id == id }) {
                            popover(for: dot.marker)
                        }
                    }
            }
        }
        .frame(height: height + Self.chrome)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    @ViewBuilder
    private func symbol(for dot: InterviewTimelineLayout.Dot) -> some View {
        let isHovered = dot.id == hoveredMarkerID
        switch dot.marker {
        case .step(let step):
            self.dot(for: step, isHovered: isHovered)
        case .ending(_, let ending):
            Self.symbol(for: ending.kind)
                .font(.system(size: isHovered ? 15 : 12))
        }
    }

    /// A green star for an offer, a red cross for a rejection, in the funnel's colors.
    @ViewBuilder
    private static func symbol(for kind: InterviewInsights.Ending.Kind) -> some View {
        switch kind {
        case .offer:
            Image(systemName: "star.fill")
                .foregroundStyle(FunnelOutcome.offer.color)
        case .rejected:
            Image(systemName: "xmark")
                .fontWeight(.bold)
                .foregroundStyle(FunnelOutcome.rejected.color)
        }
    }

    @ViewBuilder
    private func dot(for step: InterviewInsights.Step, isHovered: Bool) -> some View {
        let size = isHovered ? InterviewTimelineLayout.dotSize + 3 : InterviewTimelineLayout.dotSize
        if let outcome = step.outcome {
            Circle()
                .fill(outcome.color)
                .frame(width: size, height: size)
        } else {
            Circle()
                .strokeBorder(InterviewInsights.upcomingColor, lineWidth: 1.5)
                .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
                .frame(width: size, height: size)
        }
    }

    /// From a couple of days before the first step to a couple after the later of the last
    /// step or offer and today, so edge markers aren't cut in half.
    private var xDomain: ClosedRange<Date> {
        let first = interviews.steps.first?.date ?? interviews.now
        let last = max(interviews.processes.map(\.last).max() ?? interviews.now, interviews.now)
        let pad: TimeInterval = 2 * 86_400
        return first.addingTimeInterval(-pad)...last.addingTimeInterval(pad)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(InterviewInsights.StepOutcome.allCases) { outcome in
                legendItem(outcome.label) { Circle().fill(outcome.color) }
            }
            legendItem("Upcoming") {
                Circle().strokeBorder(InterviewInsights.upcomingColor, lineWidth: 1.5)
            }
            ForEach([InterviewInsights.Ending.Kind.offer, .rejected], id: \.self) { kind in
                HStack(spacing: 4) {
                    Self.symbol(for: kind).font(.system(size: 9))
                    Text(kind.label).foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
    }

    private func legendItem(_ label: String, @ViewBuilder symbol: () -> some View) -> some View {
        HStack(spacing: 5) {
            symbol().frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
        }
    }

    // MARK: Hover

    /// The marker nearest the pointer, if it's close enough to mean that one.
    private func marker(near point: CGPoint, in layout: InterviewTimelineLayout,
                        proxy: ChartProxy, geometry: GeometryProxy) -> String? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let origin = geometry[plotFrame].origin
        var best: (id: String, distance: CGFloat)?
        for dot in layout.dots {
            guard let position = proxy.position(for: (x: dot.marker.date, y: layout.height - dot.y)) else { continue }
            let distance = hypot(position.x + origin.x - point.x, position.y + origin.y - point.y)
            if distance <= Self.hitRadius, distance < (best?.distance ?? .infinity) {
                best = (dot.id, distance)
            }
        }
        return best?.id
    }

    @ViewBuilder
    private func popover(for marker: InterviewTimelineLayout.Marker) -> some View {
        switch marker {
        case .step(let step):
            InsightsPopoverList(title: step.title, detail: Self.companyAndRole(step.companyName, step.jobTitle)) {
                InsightsPopoverFields(fields: fields(for: step))
            }
        case .ending(let process, let ending):
            let company = process.steps.first?.companyName ?? process.label
            InsightsPopoverList(title: ending.kind.label,
                                detail: Self.companyAndRole(company, process.steps.first?.jobTitle ?? "")) {
                InsightsPopoverFields(fields: endingFields(process, date: ending.date))
            }
        }
    }

    private static func companyAndRole(_ company: String, _ role: String) -> String {
        role.trimmed.isEmpty ? company : "\(company) · \(role.trimmed)"
    }

    private func endingFields(_ process: InterviewInsights.Process, date: Date) -> [(label: String, value: String)] {
        var fields: [(label: String, value: String)] = [
            ("When", date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
        ]
        let before = process.steps.filter { $0.date <= date }
        if let first = before.first {
            let days = Int((date.timeIntervalSince(first.date) / 86_400).rounded())
            fields.append(("Took", "\(days) \(days == 1 ? "day" : "days") from the first step"))
            fields.append(("After", "\(before.count) \(before.count == 1 ? "step" : "steps")"))
        }
        return fields
    }

    private func fields(for step: InterviewInsights.Step) -> [(label: String, value: String)] {
        var fields: [(label: String, value: String)] = [
            ("When", step.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
        ]
        let length = [step.durationMinutes.map { "\($0) min" }, step.format?.rawValue].compactMap { $0 }
        if !length.isEmpty { fields.append(("Length", length.joined(separator: " · "))) }
        if !step.interviewers.trimmed.isEmpty { fields.append(("With", step.interviewers.trimmed)) }
        fields.append(("Result", step.isUpcoming ? "Upcoming" : step.result.rawValue))
        return fields
    }
}

/// Where each row and dot of the timeline goes, in points down from the top of the plot.
/// Steps close enough in time that their dots would touch are stacked into lanes within
/// their row — the first lane on the row's line, the next above it, then below, and so on —
/// and a row with lanes grows to fit them, so every step keeps a dot of its own.
struct InterviewTimelineLayout {
    struct Row {
        let process: InterviewInsights.Process
        let center: Double
    }

    /// Something drawn on a row: an interview step, or the offer or rejection the process
    /// ended in.
    enum Marker {
        case step(InterviewInsights.Step)
        case ending(InterviewInsights.Process, InterviewInsights.Ending)

        var date: Date {
            switch self {
            case .step(let step): step.date
            case .ending(_, let ending): ending.date
            }
        }

        var id: String {
            switch self {
            case .step(let step): "step-\(step.id)"
            case .ending(let process, let ending): "\(ending.kind)-\(process.applicationID)"
            }
        }

        var step: InterviewInsights.Step? {
            if case .step(let step) = self { return step }
            return nil
        }
    }

    struct Dot {
        let marker: Marker
        let lane: Int
        let y: Double
        var id: String { marker.id }
        var step: InterviewInsights.Step? { marker.step }
    }

    static let dotSize: CGFloat = 9
    /// Closest two dots can sit side by side, centre to centre, before they'd touch.
    static let minSpacing: CGFloat = 11
    static let laneSpacing: Double = 11
    static let rowHeight: Double = 28

    let rows: [Row]
    let dots: [Dot]
    let height: Double

    init(processes: [InterviewInsights.Process], domain: ClosedRange<Date>, plotWidth: CGFloat) {
        let secondsPerPoint = domain.upperBound.timeIntervalSince(domain.lowerBound) / Double(max(plotWidth, 1))
        let minGap = Double(Self.minSpacing) * secondsPerPoint

        var rows: [Row] = []
        var dots: [Dot] = []
        var top = 0.0
        for process in processes {
            // Oldest first: each marker takes the first lane whose last one is far enough back.
            var markers = process.steps.map(Marker.step)
            markers += process.endings.map { .ending(process, $0) }
            markers.sort { $0.date < $1.date }
            var laneEnds: [Date] = []
            var placed: [(marker: Marker, lane: Int)] = []
            for marker in markers {
                if let lane = laneEnds.firstIndex(where: { marker.date.timeIntervalSince($0) >= minGap }) {
                    laneEnds[lane] = marker.date
                    placed.append((marker, lane))
                } else {
                    laneEnds.append(marker.date)
                    placed.append((marker, laneEnds.count - 1))
                }
            }
            // Lanes alternate above and below the line, so the furthest is half the count away.
            let reach = Double(laneEnds.count / 2) * Self.laneSpacing
            let height = max(Self.rowHeight, reach * 2 + Self.rowHeight - Self.laneSpacing)
            let center = top + height / 2
            rows.append(Row(process: process, center: center))
            for (marker, lane) in placed {
                dots.append(Dot(marker: marker, lane: lane, y: center + Self.offset(ofLane: lane)))
            }
            top += height
        }
        self.rows = rows
        self.dots = dots
        height = top
    }

    /// 0 on the line, then one lane above, one below, two above, …
    static func offset(ofLane lane: Int) -> Double {
        guard lane > 0 else { return 0 }
        let step = Double((lane + 1) / 2) * laneSpacing
        return lane.isMultiple(of: 2) ? step : -step
    }
}

extension InterviewInsights.Ending.Kind {
    var label: String {
        switch self {
        case .offer: "Offer"
        case .rejected: "Rejected"
        }
    }
}
