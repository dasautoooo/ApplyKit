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
            InsightsKPITile(title: "Applied", value: "\(kpis.applied)")
            rateTile("Response rate", count: kpis.responded)
            rateTile("Interview rate", count: kpis.interviewed)
            rateTile("Offer rate", count: kpis.offers)
            InsightsKPITile(
                title: "Median time to reply",
                value: kpis.medianDaysToResponse.map { "\(Int($0.rounded())) d" } ?? "–",
                detail: "Applied → first response"
            )
        }
    }

    private func rateTile(_ title: String, count: Int) -> some View {
        InsightsKPITile(
            title: title,
            value: kpis.rate(count).map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–",
            detail: "\(count) of \(kpis.applied)"
        )
    }
}

/// The interview steps at a glance: how many, how long, how they went, what's next.
struct InterviewKPIRow: View {
    let insights: ApplicationInsights

    private var interviews: InterviewInsights { insights.interviews }

    var body: some View {
        let kpis = interviews.kpis
        let funnel = insights.kpis
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            InsightsKPITile(
                title: "Interviews",
                value: "\(kpis.held)",
                detail: kpis.held == 0 ? nil : "at \(kpis.companies) \(kpis.companies == 1 ? "company" : "companies")"
            )
            InsightsKPITile(
                title: "Time interviewing",
                value: kpis.held == 0 ? "–" : "\(InterviewInsights.formatHours(kpis.heldHours)) h",
                detail: "Screens and rounds"
            )
            InsightsKPITile(
                title: "Pass rate",
                value: kpis.passRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–",
                detail: kpis.decided == 0 ? "No results yet" : "\(kpis.passed) of \(kpis.decided) decided"
            )
            InsightsKPITile(
                title: "Interview → offer",
                value: funnel.interviewToOfferRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–",
                detail: conversionDetail(funnel)
            )
            InsightsKPITile(
                title: "Upcoming",
                value: "\(kpis.upcomingThisWeek)",
                detail: kpis.next.map(nextDetail) ?? "Nothing scheduled"
            )
        }
    }

    /// "1 of 4 finished", noting how many interview loops are still undecided.
    private func conversionDetail(_ kpis: ApplicationInsights.KPIs) -> String {
        guard kpis.finishedAfterInterviewing > 0 else {
            return kpis.interviewingNow > 0 ? "\(kpis.interviewingNow) still in progress" : "No interview loops yet"
        }
        return "\(kpis.offersAfterInterviewing) of \(kpis.finishedAfterInterviewing) finished"
            + (kpis.interviewingNow > 0 ? " · \(kpis.interviewingNow) ongoing" : "")
    }

    /// The next step's company and day: a weekday within the week, a date beyond it.
    private func nextDetail(_ step: InterviewInsights.Step) -> String {
        let soon = step.date.timeIntervalSince(interviews.now) < 6 * 86_400
        let day = soon
            ? step.date.formatted(.dateTime.weekday(.abbreviated))
            : step.date.formatted(.dateTime.month(.abbreviated).day())
        return "Next: \(step.companyName), \(day)"
    }
}

struct InsightsKPITile: View {
    let title: String
    let value: String
    var detail: String?

    var body: some View {
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
                .lineLimit(1)
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
