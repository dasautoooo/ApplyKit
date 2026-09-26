//
//  PipelineSnapshotChart.swift
//  ApplyKit
//

import Charts
import SwiftUI

/// Where every application stands right now, pre-apply ones included.
struct PipelineSnapshotChart: View {
    let insights: ApplicationInsights
    @State private var selectedAngle: Int?

    private var total: Int { insights.snapshot.reduce(0) { $0 + $1.count } }

    var body: some View {
        if insights.snapshot.isEmpty {
            InsightsEmptyChart(message: "No applications in this range.", height: InsightsLayout.gridChartHeight)
        } else {
            Chart(insights.snapshot) { slice in
                SectorMark(
                    angle: .value("Applications", slice.count),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .cornerRadius(3)
                .foregroundStyle(by: .value("Status", slice.category.label))
                .opacity(selected == nil || selected?.id == slice.id ? 1 : 0.4)
            }
            .chartForegroundStyleScale(
                domain: ApplicationInsights.SnapshotCategory.allCases.map(\.label),
                range: ApplicationInsights.SnapshotCategory.allCases.map(\.color)
            )
            .chartAngleSelection(value: $selectedAngle)
            .chartLegend(position: .trailing, alignment: .center)
            .chartBackground { proxy in
                GeometryReader { geometry in
                    if let frame = proxy.plotFrame {
                        let rect = geometry[frame]
                        centerLabel.position(x: rect.midX, y: rect.midY)
                    }
                }
            }
            .frame(height: InsightsLayout.gridChartHeight)
        }
    }

    private var centerLabel: some View {
        VStack(spacing: 0) {
            Text("\(selected?.count ?? total)")
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(selected?.category.label ?? "applications")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The angle selection reports a running total; find the slice whose span contains it.
    private var selected: ApplicationInsights.SnapshotSlice? {
        guard let selectedAngle else { return nil }
        var running = 0
        for slice in insights.snapshot {
            running += slice.count
            if selectedAngle <= running { return slice }
        }
        return nil
    }
}
