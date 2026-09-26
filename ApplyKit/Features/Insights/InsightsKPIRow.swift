//
//  InsightsKPIRow.swift
//  ApplyKit
//

import AppKit
import SwiftUI

struct InsightsKPIRow: View {
    let kpis: ApplicationInsights.KPIs

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            tile("Applied", value: "\(kpis.applied)", detail: nil)
            rateTile("Response rate", count: kpis.responded)
            rateTile("Interview rate", count: kpis.interviewed)
            rateTile("Offer rate", count: kpis.offers)
            tile(
                "Median time to reply",
                value: kpis.medianDaysToResponse.map { "\(Int($0.rounded())) d" } ?? "–",
                detail: "Applied → first response"
            )
        }
    }

    private func rateTile(_ title: String, count: Int) -> some View {
        tile(
            title,
            value: kpis.rate(count).map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–",
            detail: "\(count) of \(kpis.applied)"
        )
    }

    private func tile(_ title: String, value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(detail ?? " ")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        }
    }
}
