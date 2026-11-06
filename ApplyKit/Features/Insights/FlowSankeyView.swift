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
    @State private var hoveredFlowID: String?
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
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            hoveredFlowID = layout.flowID(at: point)
                        case .ended:
                            hoveredFlowID = nil
                        }
                    }
                }
                .frame(height: SankeyLayout.height(for: insights))

                if !isExport {
                    Text(readout)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var readout: String {
        guard let flow = insights.flows.first(where: { $0.id == hoveredFlowID }) else {
            return "Hover a ribbon for its count."
        }
        let target = switch flow.to {
        case .stage(let stage): stage.label
        case .outcome(let outcome): outcome.label
        }
        let share = count(at: flow.from).map { Double(flow.count) / Double($0) }
        let shareText = share.map { " (\($0.formatted(.percent.precision(.fractionLength(0)))) of \(flow.from.label))" } ?? ""
        return "\(flow.from.label) → \(target): \(flow.count)\(shareText)"
    }

    private func count(at stage: FunnelStage) -> Int? {
        insights.reached.first { $0.stage == stage }?.count
    }

    private func draw(_ layout: SankeyLayout, in context: inout GraphicsContext) {
        for ribbon in layout.ribbons {
            let isHovered = ribbon.flow.id == hoveredFlowID
            let base = hoveredFlowID == nil ? 0.3 : (isHovered ? 0.55 : 0.15)
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

        /// The node plus a margin, and for an outcome node the label beside it.
        var hitRect: CGRect {
            let padded = rect.insetBy(dx: -4, dy: -5)
            guard labelAnchor == .leading else { return padded }
            return padded.union(CGRect(x: labelPoint.x, y: labelPoint.y - 9, width: 110, height: 18))
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

    /// The flow under the pointer: a ribbon it's inside, else an outcome node or its label,
    /// else the ribbon whose centre line it's nearest, within a few points.
    func flowID(at point: CGPoint) -> String? {
        if let ribbon = ribbons.last(where: { $0.path.contains(point) }) { return ribbon.flow.id }
        if let node = nodes.last(where: { $0.flowID != nil && $0.hitRect.contains(point) }) { return node.flowID }
        for band in Self.hitTolerances.indices {
            if let ribbon = ribbons.last(where: { $0.hitBands[band].contains(point) }) { return ribbon.flow.id }
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
                labelAnchor: .bottomLeading
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
                labelAnchor: .bottomLeading
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
