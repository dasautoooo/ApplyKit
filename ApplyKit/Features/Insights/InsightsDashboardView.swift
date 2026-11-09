//
//  InsightsDashboardView.swift
//  ApplyKit
//

import SwiftUI

/// How applications move through the pipeline: KPI tiles over a grid of charts, all drawn
/// from one `ApplicationInsights` so every card agrees under the same filters.
struct InsightsDashboardView: View {
    @Environment(AppDataStore.self) private var store
    @AppStorage("insights.range") private var range: InsightsRange = .ninetyDays
    /// The moment the numbers are anchored to: the date range's start and whether a scheduled
    /// round has happened yet. Edits show up on their own; Refresh re-anchors this to now.
    @State private var refreshedAt = Date()

    var body: some View {
        InsightsDashboardContent(
            applications: filteredApplications,
            now: refreshedAt,
            range: $range,
            onRefresh: { refreshedAt = Date() }
        )
    }

    /// Archived applications are included: a rejection usually gets archived, and leaving
    /// those out would show a funnel with no one ever turned down.
    private var filteredApplications: [JobApplication] {
        let start = range.startDate(relativeTo: refreshedAt)
        return store.applications.filter { application in
            guard let start else { return true }
            // Applied date when there is one: the funnel is about what happened after applying.
            return (application.dateApplied ?? application.dateSaved) >= start
        }
    }
}

enum InsightsRange: String, CaseIterable, Identifiable {
    case thirtyDays = "30 Days"
    case ninetyDays = "90 Days"
    case twelveMonths = "12 Months"
    case all = "All Time"

    var id: String { rawValue }

    func startDate(relativeTo now: Date) -> Date? {
        let calendar = Calendar.current
        switch self {
        case .thirtyDays: return calendar.date(byAdding: .day, value: -30, to: now)
        case .ninetyDays: return calendar.date(byAdding: .day, value: -90, to: now)
        case .twelveMonths: return calendar.date(byAdding: .month, value: -12, to: now)
        case .all: return nil
        }
    }
}

/// Split from the store-reading wrapper so previews can hand it fixture applications.
private struct InsightsDashboardContent: View {
    let applications: [JobApplication]
    let now: Date
    @Binding var range: InsightsRange
    let onRefresh: () -> Void

    var body: some View {
        let insights = ApplicationInsights(applications: applications, now: now)
        Group {
            if applications.isEmpty {
                ContentUnavailableView(
                    "No applications in this range",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Widen the date range.")
                )
            } else {
                dashboard(insights)
            }
        }
        .navigationTitle("Insights")
        .navigationSubtitle("Updated \(now.formatted(date: .omitted, time: .shortened))")
        .toolbar {
            ToolbarItem {
                InsightsShareMenu(
                    name: "Job Search Insights \(now.formatted(.iso8601.year().month().day()))",
                    width: 1100,
                    label: "Share",
                    content: AnyView(exportedDashboard(insights))
                )
            }
            ToolbarItem {
                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Recalculate as of now (⌘R)")
            }
            ToolbarItem {
                Picker("Range", selection: $range) {
                    ForEach(InsightsRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.menu)
                .help("Applications applied to (or saved, if not yet applied) within this range")
            }
        }
    }

    private func dashboard(_ insights: ApplicationInsights) -> some View {
        ScrollView {
            InsightsDashboardBody(insights: insights)
                .padding(20)
        }
    }

    /// The whole dashboard as shared: titled with its range and date, since an image posted
    /// elsewhere loses the window around it.
    private func exportedDashboard(_ insights: ApplicationInsights) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Job Search Insights")
                    .font(.title2.weight(.semibold))
                Text("\(range.rawValue) · as of \(now.formatted(date: .abbreviated, time: .omitted))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            InsightsDashboardBody(insights: insights, isExport: true)
        }
    }
}

/// KPI tiles over the charts. Shared by the scrolling dashboard and its exported image.
private struct InsightsDashboardBody: View {
    let insights: ApplicationInsights
    var isExport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InsightsKPIRow(kpis: insights.kpis)
            InterviewKPIRow(interviews: insights.interviews)

            InsightsCard(
                title: "Funnel",
                subtitle: "How far applications got, and what happened at each stage",
                footnote: inferredFootnote,
                exportWidth: 1000,
                isExport: isExport
            ) {
                StageFunnelChart(insights: insights)
            }

            InsightsCard(title: "Flow", subtitle: "Where applications went from each stage",
                         exportWidth: 1000, isExport: isExport) {
                FlowSankeyView(insights: insights)
            }

            InsightsCard(title: "Interview timelines", subtitle: "Each company's interview steps over time",
                         exportWidth: 1000, isExport: isExport) {
                InterviewTimelineChart(interviews: insights.interviews)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 16, alignment: .top)],
                      alignment: .leading, spacing: 16) {
                InsightsCard(
                    title: "Pipeline right now",
                    subtitle: "Where every application stands today",
                    footnote: "Includes archived applications, except ones you never applied to.",
                    isExport: isExport
                ) {
                    PipelineSnapshotChart(insights: insights)
                }
                InsightsCard(title: "Activity", subtitle: "Applications sent and responses received, by week",
                             isExport: isExport) {
                    ActivityChart(insights: insights)
                }
                InsightsCard(
                    title: "Time to response",
                    subtitle: "Median wait (dot) and middle half of waits (bar)",
                    footnote: "Approximate dates from older applications are left out.",
                    isExport: isExport
                ) {
                    TimeToResponseChart(insights: insights)
                }
                InsightsCard(title: "Fit score vs outcome", subtitle: "Furthest stage reached by the tailor's fit score",
                             isExport: isExport) {
                    FitScoreOutcomeChart(insights: insights)
                }
                InsightsCard(title: "Pass rate by round type", subtitle: "How each kind of step went, once it happened",
                             isExport: isExport) {
                    RoundTypeOutcomeChart(interviews: insights.interviews)
                }
                InsightsCard(
                    title: "Interview load",
                    subtitle: "Hours of interviews per week, scheduled ones included",
                    footnote: "Steps without a length count as 30 min for a screen, 1 h for a round.",
                    isExport: isExport
                ) {
                    InterviewLoadChart(interviews: insights.interviews)
                }
            }
        }
    }

    private var inferredFootnote: String? {
        guard insights.inferredCount > 0 else { return nil }
        return "\(insights.inferredCount) application\(insights.inferredCount == 1 ? " has" : "s have") approximate history reconstructed from saved dates."
    }
}

#if DEBUG
private enum InsightsPreviewData {
    /// A spread of journeys: early drop-offs, multi-round interviews, an offer, and ghosting.
    static var applications: [JobApplication] {
        let now = Date()
        func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

        func make(_ company: String, fit: Double?, applied: Double, screenDaysAgo: Double? = nil,
                  steps: [(days: Double, status: ApplicationStatus)] = [],
                  rounds: [(days: Double, type: InterviewType, result: InterviewResult)] = []) -> JobApplication {
            var application = JobApplication(companyName: company, jobTitle: "Software Engineer")
            application.dateSaved = daysAgo(applied + 3)
            application.timeline = [ApplicationEvent(date: application.dateSaved, kind: .created)]
            application.fitScore = fit
            application.setStatus(rawValue: ApplicationStatus.applied.rawValue, at: daysAgo(applied))
            for round in rounds {
                application.recordInterviewStep(ApplicationEvent(
                    date: daysAgo(round.days), kind: .interview,
                    interviewTypeRaw: round.type.rawValue, interviewResultRaw: round.result.rawValue,
                    interview: InterviewDetails(durationMinutes: round.type == .onsite ? 240 : 60,
                                                formatRaw: InterviewFormat.video.rawValue,
                                                interviewers: "Sam Rivera")
                ))
            }
            for step in steps {
                application.setStatus(rawValue: step.status.rawValue, at: daysAgo(step.days))
            }
            if let screen = screenDaysAgo {
                application.recordInterviewStep(ApplicationEvent(
                    date: daysAgo(screen), kind: .interview,
                    interviewTypeRaw: InterviewType.recruiterScreen.rawValue,
                    interviewResultRaw: InterviewResult.passed.rawValue
                ))
            }
            return application
        }

        return [
            make("Northwind", fit: 8.5, applied: 60, screenDaysAgo: 55, steps: [(20, .offer)],
                 rounds: [(48, .coding, .passed), (40, .systemDesign, .passed), (30, .onsite, .passed)]),
            make("Contoso", fit: 7.5, applied: 50, screenDaysAgo: 44, steps: [(25, .rejected)],
                 rounds: [(38, .coding, .passed), (29, .behavioral, .didNotAdvance)]),
            make("Fabrikam", fit: 6.0, applied: 45, steps: [(30, .rejected)]),
            make("Tailspin", fit: 5.5, applied: 40, steps: [(10, .ghosted)]),
            make("Litware", fit: 7.0, applied: 30, screenDaysAgo: 24,
                 rounds: [(15, .phoneScreen, .passed), (5, .coding, .passed), (4.95, .behavioral, .passed),
                          (4.2, .hiringManager, .awaiting), (-3, .systemDesign, .scheduled)]),
            make("Adventure Works", fit: 9.0, applied: 28, screenDaysAgo: 25,
                 rounds: [(18, .onlineAssessment, .passed), (-5, .coding, .scheduled)]),
            make("Proseware", fit: 4.5, applied: 25),
            make("Wingtip", fit: nil, applied: 20, steps: [(12, .rejected)]),
            make("Woodgrove", fit: 6.5, applied: 18, screenDaysAgo: 14, steps: [(6, .withdrawn)]),
            make("Relecloud", fit: 8.0, applied: 12),
            make("Alpine Ski House", fit: 5.0, applied: 8),
            JobApplication(companyName: "Humongous", jobTitle: "iOS Engineer", status: .interested)
        ]
    }
}

#Preview {
    @Previewable @State var range = InsightsRange.all
    NavigationStack {
        InsightsDashboardContent(applications: InsightsPreviewData.applications, now: Date(),
                                 range: $range, onRefresh: {})
    }
    .frame(width: 1000, height: 1200)
}
#endif
