//
//  FlowSankeyView.swift
//  ApplyKit
//

import SwiftUI

/// Stage-to-stage flow with drop-offs. Swift Charts has no Sankey mark, so this is drawn with
/// a Canvas: pipeline stages run left to right ending in Offer, which any stage can feed, and
/// whatever neither advances nor gets an offer peels off downward into that stage's outcome
/// nodes (Still active, Rejected, ...).
struct FlowSankeyView: View {
    let insights: ApplicationInsights
    /// What the pointer is over, updated on every move: drives the highlight and the caption.
    /// Resting on it opens a popover listing its applications.
    @State private var hovered: SankeyHoverTarget?
    @Environment(\.isInsightsExport) private var isExport

    var body: some View {
        if insights.reached.isEmpty {
            InsightsEmptyChart(message: "Nothing applied to in this range yet.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { proxy in
                    let layout = SankeyLayout(insights: insights, width: proxy.size.width)
                    Canvas { context, _ in
                        draw(layout, in: &context)
                    }
                    .insightsHoverPopover(hovered: $hovered, hitTest: layout.target(at:)) { target in
                        FlowPopoverContent(insights: insights, target: target)
                    }
                }
                .frame(height: SankeyLayout.height(for: insights))

                if !isExport {
                    Text(hovered.map { FlowPopoverContent(insights: insights, target: $0).summary }
                         ?? "Hover a ribbon or stage to see its applications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Drawing

    private func isHighlighted(_ flow: ApplicationInsights.Flow) -> Bool {
        switch hovered {
        case .flow(let id): flow.id == id
        case .stage(let stage): flow.from == stage || flow.to == .stage(stage)
        case nil: false
        }
    }

    private func draw(_ layout: SankeyLayout, in context: inout GraphicsContext) {
        for ribbon in layout.ribbons {
            let base = hovered == nil ? 0.3 : (isHighlighted(ribbon.flow) ? 0.55 : 0.15)
            context.fill(ribbon.path, with: .color(ribbon.color.opacity(base)))
        }

        for node in layout.nodes {
            context.fill(Path(roundedRect: node.rect, cornerRadius: 2), with: .color(node.color))
            let text = Text(node.label).font(.caption).foregroundStyle(.secondary)
                + Text(" \(node.count)").font(.caption.weight(.semibold)).foregroundStyle(.primary)
            context.draw(text, at: node.labelPoint, anchor: node.labelAnchor)
        }
    }
}

/// What the pointer is over in the Sankey: a ribbon (or the outcome node it ends in), or a
/// stage's column.
enum SankeyHoverTarget: Hashable {
    case flow(String)
    case stage(FunnelStage)
}

/// The applications behind one ribbon or stage, laid out like a standard macOS popover: a
/// title and summary over a plain two-line list.
private struct FlowPopoverContent: View {
    let insights: ApplicationInsights
    let target: SankeyHoverTarget

    /// The Applied end of the funnel can hold most of the search, so its lists are cut short.
    private static let cappedRowCount = 8

    var body: some View {
        let members = members
        let shown = isCapped ? Array(members.prefix(Self.cappedRowCount)) : members
        let hidden = members.count - shown.count

        InsightsPopoverList(title: title, detail: detail, footer: hidden > 0 ? "\(hidden) more" : nil) {
            ForEach(shown, id: \.applicationID) { member in
                InsightsPopoverRow(
                    primary: member.companyName.trimmed.isEmpty ? "Untitled" : member.companyName,
                    secondary: member.jobTitle.trimmed.isEmpty ? "No role" : member.jobTitle,
                    trailing: member.isArchived ? "Archived" : nil
                )
            }
        }
    }

    // MARK: Text

    private var flow: ApplicationInsights.Flow? {
        guard case .flow(let id) = target else { return nil }
        return insights.flows.first { $0.id == id }
    }

    private var title: String {
        switch target {
        case .stage(let stage):
            return stage.label
        case .flow:
            guard let flow else { return "" }
            let destination = switch flow.to {
            case .stage(let stage): stage.label
            case .outcome(let outcome): outcome.label
            }
            return "\(flow.from.label) → \(destination)"
        }
    }

    /// The count and its share: of the source stage for a ribbon, of everything applied to
    /// for a stage (the same percentage the Funnel shows).
    private var detail: String {
        switch target {
        case .stage(let stage):
            let reached = count(at: stage) ?? 0
            let noun = reached == 1 ? "application" : "applications"
            guard stage != .applied, let share = share(reached, of: .applied) else { return "\(reached) \(noun)" }
            return "\(reached) \(noun) · \(share) of applied"
        case .flow:
            guard let flow else { return "" }
            let noun = flow.count == 1 ? "application" : "applications"
            guard let share = share(flow.count, of: flow.from) else { return "\(flow.count) \(noun)" }
            return "\(flow.count) \(noun) · \(share) of \(flow.from.label)"
        }
    }

    /// One line for the caption under the graph.
    var summary: String { "\(title): \(detail)" }

    private var members: [ApplicationJourney] {
        switch target {
        case .flow: flow?.members ?? []
        case .stage(let stage): insights.stageMembers[stage] ?? []
        }
    }

    /// Only the Applied stage and the ways out of it are cut short; from the screen on, every
    /// application is listed.
    private var isCapped: Bool {
        switch target {
        case .stage(let stage):
            return stage == .applied
        case .flow:
            guard let flow, flow.from == .applied else { return false }
            if case .outcome = flow.to { return true }
            return false
        }
    }

    private func count(at stage: FunnelStage) -> Int? {
        insights.reached.first { $0.stage == stage }?.count
    }

    private func share(_ part: Int, of stage: FunnelStage) -> String? {
        guard let total = count(at: stage), total > 0 else { return nil }
        return (Double(part) / Double(total)).formatted(.percent.precision(.fractionLength(0)))
    }
}

/// Geometry for the Sankey, shared by drawing and hit-testing so hover matches what's drawn.
struct SankeyLayout {
    struct Node {
        let rect: CGRect
        let color: Color
        let label: String
        let count: Int
        let labelPoint: CGPoint
        let labelAnchor: UnitPoint
        /// Outcome nodes stand for one flow, so hovering them — or their label — shows it.
        var flowID: String?
        /// Set on stage columns (Offer included), which show everyone who reached them.
        var stage: FunnelStage?

        /// The node plus a margin, and its label: beside an outcome node, above a stage column.
        var hitRect: CGRect {
            let padded = rect.insetBy(dx: -4, dy: -5)
            let label = labelAnchor == .leading
                ? CGRect(x: labelPoint.x, y: labelPoint.y - 9, width: 110, height: 18)
                : CGRect(x: labelPoint.x, y: labelPoint.y - 16, width: 80, height: 16)
            return padded.union(label)
        }
    }

    struct Ribbon {
        let flow: ApplicationInsights.Flow
        let path: Path
        let color: Color
        /// Bands of growing width around the ribbon's centre line, so one a pixel thick can
        /// still be hovered; the narrowest band that catches the pointer decides between
        /// neighbours.
        let hitBands: [Path]
    }

    /// Half-widths of the hover bands around each ribbon's centre line.
    private static let hitTolerances: [CGFloat] = [3, 6, 9]

    /// What's under the pointer: a ribbon it's inside, else an outcome node or its label, else
    /// a stage column or its label, else the ribbon whose centre line it's nearest, within a
    /// few points. Columns come before the near-miss bands so a thin ribbon leaving a column
    /// doesn't steal the hover from it.
    func target(at point: CGPoint) -> SankeyHoverTarget? {
        if let ribbon = ribbons.last(where: { $0.path.contains(point) }) { return .flow(ribbon.flow.id) }
        if let id = nodes.last(where: { $0.flowID != nil && $0.hitRect.contains(point) })?.flowID {
            return .flow(id)
        }
        if let stage = nodes.last(where: { $0.stage != nil && $0.hitRect.contains(point) })?.stage {
            return .stage(stage)
        }
        for band in Self.hitTolerances.indices {
            if let ribbon = ribbons.last(where: { $0.hitBands[band].contains(point) }) { return .flow(ribbon.flow.id) }
        }
        return nil
    }

    private static func hitBands(from x0: CGFloat, y: CGFloat, bendingAt bend: CGFloat? = nil,
                                 to x1: CGFloat, ty: CGFloat) -> [Path] {
        let start = max(bend ?? x0, x0)
        let mid = (start + x1) / 2
        var centre = Path()
        centre.move(to: CGPoint(x: x0, y: y))
        centre.addLine(to: CGPoint(x: start, y: y))
        centre.addCurve(to: CGPoint(x: x1, y: ty), control1: CGPoint(x: mid, y: y), control2: CGPoint(x: mid, y: ty))
        return hitTolerances.map { centre.strokedPath(StrokeStyle(lineWidth: $0 * 2, lineCap: .butt)) }
    }

    static let labelTop: CGFloat = 18
    static let mainHeight: CGFloat = 150
    static let exitGap: CGFloat = 16
    static let nodeWidth: CGFloat = 10
    static let minNodeHeight: CGFloat = 2

    var nodes: [Node] = []
    var ribbons: [Ribbon] = []

    /// Height depends only on the data, so the card can size itself before layout.
    static func height(for insights: ApplicationInsights) -> CGFloat {
        let scale = self.scale(for: insights)
        let exitStack = Dictionary(grouping: exitFlows(insights), by: \.from).values.map { flows in
            flows.reduce(0) { $0 + max(CGFloat($1.count) * scale, minNodeHeight) + exitGap }
        }.max() ?? 0
        return labelTop + mainHeight + 28 + exitStack + 4
    }

    private static func scale(for insights: ApplicationInsights) -> CGFloat {
        mainHeight / CGFloat(max(insights.reached.first?.count ?? 1, 1))
    }

    private static func exitFlows(_ insights: ApplicationInsights) -> [ApplicationInsights.Flow] {
        insights.flows.filter { if case .outcome = $0.to { true } else { false } }
    }

    init(insights: ApplicationInsights, width: CGFloat) {
        // Offer is the final column, after the pipeline stages, fed from whichever stage each
        // offer followed.
        let stages = insights.reached.filter { $0.stage != .offer }
        guard !stages.isEmpty else { return }
        let offerCount = insights.reached.first { $0.stage == .offer }?.count
        let scale = Self.scale(for: insights)
        // Room on the right for the last column's labels: the last stage's outcome nodes when
        // it's the last column, or the Offer label plus whatever of them pokes past it.
        let columns = stages.count - 1 + (offerCount == nil ? 0 : 1)
        let margin: CGFloat = offerCount == nil ? 150 : 90
        let column = (width - Self.nodeWidth - margin) / CGFloat(max(columns, 1))
        let exitTop = Self.labelTop + Self.mainHeight + 28

        func x(_ index: Int) -> CGFloat { CGFloat(index) * column }

        // Offer ribbons keep their height until past the last stage, then bend into the Offer
        // node. Stage nodes only shrink to the right, so a ribbon leaving below one stage's
        // advancing flow clears every later node. Stacked latest stage on top so the bends
        // never cross.
        let offerX = x(stages.count)
        let bendX = x(stages.count - 1) + Self.nodeWidth
        var offerSlots: [FunnelStage: CGFloat] = [:]
        if let offerCount {
            var y = Self.labelTop
            let offerFlows = insights.flows.filter { $0.to == .stage(.offer) }
            for flow in offerFlows.sorted(by: { $0.from > $1.from }) {
                offerSlots[flow.from] = y
                y += CGFloat(flow.count) * scale
            }
            let rect = CGRect(x: offerX, y: Self.labelTop, width: Self.nodeWidth,
                              height: max(CGFloat(offerCount) * scale, Self.minNodeHeight))
            nodes.append(Node(
                rect: rect,
                color: FunnelOutcome.offer.color,
                label: FunnelStage.offer.label,
                count: offerCount,
                labelPoint: CGPoint(x: rect.minX, y: Self.labelTop - 4),
                labelAnchor: .bottomLeading,
                stage: .offer
            ))
        }

        for (index, entry) in stages.enumerated() {
            let rect = CGRect(x: x(index), y: Self.labelTop, width: Self.nodeWidth,
                              height: max(CGFloat(entry.count) * scale, Self.minNodeHeight))
            nodes.append(Node(
                rect: rect,
                color: FunnelOutcome.advanced.color,
                label: entry.stage.label,
                count: entry.count,
                labelPoint: CGPoint(x: rect.minX, y: Self.labelTop - 4),
                labelAnchor: .bottomLeading,
                stage: entry.stage
            ))

            // Stacked inside the node: advancing flow on top, then offers, then each way out.
            var sourceY = rect.minY
            let outgoing = insights.flows.filter { $0.from == entry.stage }
            if let advance = outgoing.first(where: { if case .stage(let next) = $0.to { next != .offer } else { false } }),
               index + 1 < stages.count {
                let height = CGFloat(advance.count) * scale
                let target = CGRect(x: x(index + 1), y: Self.labelTop, width: Self.nodeWidth, height: height)
                ribbons.append(Ribbon(
                    flow: advance,
                    path: Self.band(from: rect.maxX, y0: sourceY, y1: sourceY + height,
                                    to: target.minX, ty0: target.minY, ty1: target.maxY),
                    color: FunnelOutcome.advanced.color,
                    hitBands: Self.hitBands(from: rect.maxX, y: sourceY + height / 2,
                                            to: target.minX, ty: target.midY)
                ))
                sourceY += height
            }

            if let offer = outgoing.first(where: { $0.to == .stage(.offer) }),
               let targetTop = offerSlots[entry.stage] {
                let height = CGFloat(offer.count) * scale
                ribbons.append(Ribbon(
                    flow: offer,
                    path: Self.band(from: rect.maxX, y0: sourceY, y1: sourceY + height, bendingAt: bendX,
                                    to: offerX, ty0: targetTop, ty1: targetTop + height),
                    color: FunnelOutcome.offer.color,
                    hitBands: Self.hitBands(from: rect.maxX, y: sourceY + height / 2, bendingAt: bendX,
                                            to: offerX, ty: targetTop + height / 2)
                ))
                sourceY += height
            }

            var targetY = exitTop
            let exitX = x(index) + min(column * 0.5, 70)
            for flow in outgoing {
                guard case .outcome(let outcome) = flow.to else { continue }
                let height = CGFloat(flow.count) * scale
                let nodeHeight = max(height, Self.minNodeHeight)
                let target = CGRect(x: exitX, y: targetY, width: Self.nodeWidth, height: nodeHeight)
                ribbons.append(Ribbon(
                    flow: flow,
                    path: Self.band(from: rect.maxX, y0: sourceY, y1: sourceY + height,
                                    to: target.minX, ty0: target.minY, ty1: target.minY + height),
                    color: outcome.color,
                    hitBands: Self.hitBands(from: rect.maxX, y: sourceY + height / 2,
                                            to: target.minX, ty: target.minY + height / 2)
                ))
                nodes.append(Node(
                    rect: target,
                    color: outcome.color,
                    label: outcome.label,
                    count: flow.count,
                    labelPoint: CGPoint(x: target.maxX + 5, y: target.midY),
                    labelAnchor: .leading,
                    flowID: flow.id
                ))
                sourceY += height
                targetY += nodeHeight + Self.exitGap
            }
        }
    }

    /// A ribbon whose two edges are matching S-curves between a source and a target band,
    /// running straight from the source until `bend` when one is given.
    private static func band(from x0: CGFloat, y0: CGFloat, y1: CGFloat, bendingAt bend: CGFloat? = nil,
                             to x1: CGFloat, ty0: CGFloat, ty1: CGFloat) -> Path {
        let start = max(bend ?? x0, x0)
        let mid = (start + x1) / 2
        var path = Path()
        path.move(to: CGPoint(x: x0, y: y0))
        path.addLine(to: CGPoint(x: start, y: y0))
        path.addCurve(to: CGPoint(x: x1, y: ty0),
                      control1: CGPoint(x: mid, y: y0), control2: CGPoint(x: mid, y: ty0))
        path.addLine(to: CGPoint(x: x1, y: ty1))
        path.addCurve(to: CGPoint(x: start, y: y1),
                      control1: CGPoint(x: mid, y: ty1), control2: CGPoint(x: mid, y: y1))
        path.addLine(to: CGPoint(x: x0, y: y1))
        path.closeSubpath()
        return path
    }
}
