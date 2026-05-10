//
//  StableSidebarSplit.swift
//  ApplyKit
//

import AppKit
import SwiftUI
struct StableSidebarSplit<Sidebar: View, Detail: View>: NSViewRepresentable {
    @Binding var sidebarWidth: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let detail: Detail

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autoresizesSubviews = true
        splitView.delegate = context.coordinator

        let sidebarHost = NSHostingView(rootView: sidebar)
        let detailHost = NSHostingView(rootView: detail)
        sidebarHost.translatesAutoresizingMaskIntoConstraints = false
        detailHost.translatesAutoresizingMaskIntoConstraints = false

        splitView.addArrangedSubview(sidebarHost)
        splitView.addArrangedSubview(detailHost)

        context.coordinator.sidebarHost = sidebarHost
        context.coordinator.detailHost = detailHost

        DispatchQueue.main.async {
            context.coordinator.applySidebarWidth(to: splitView)
        }

        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sidebarHost?.rootView = sidebar
        context.coordinator.detailHost?.rootView = detail
        context.coordinator.applySidebarWidth(to: splitView)
    }

    private func clamp(_ width: CGFloat) -> CGFloat {
        min(max(width, minWidth), maxWidth)
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        var parent: StableSidebarSplit
        var sidebarHost: NSHostingView<Sidebar>?
        var detailHost: NSHostingView<Detail>?
        private var isApplyingWidth = false

        init(_ parent: StableSidebarSplit) {
            self.parent = parent
        }

        func applySidebarWidth(to splitView: NSSplitView) {
            guard splitView.arrangedSubviews.count == 2 else { return }
            let desired = clampedSidebarWidth(for: splitView)
            let current = splitView.arrangedSubviews[0].frame.width

            guard current == 0 || abs(current - desired) > 1 else { return }
            isApplyingWidth = true
            splitView.setPosition(desired, ofDividerAt: 0)
            isApplyingWidth = false
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMinCoordinate proposedMinimumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            parent.minWidth
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMaxCoordinate proposedMaximumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            clampedMaxWidth(for: splitView)
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard !isApplyingWidth,
                  let splitView = notification.object as? NSSplitView,
                  let sidebar = splitView.arrangedSubviews.first else {
                return
            }

            let width = clamp(sidebar.frame.width, in: splitView)
            if abs(parent.sidebarWidth - width) > 1 {
                parent.sidebarWidth = width
            }
        }

        private func clampedSidebarWidth(for splitView: NSSplitView) -> CGFloat {
            clamp(parent.sidebarWidth, in: splitView)
        }

        private func clamp(_ width: CGFloat, in splitView: NSSplitView) -> CGFloat {
            min(max(width, parent.minWidth), clampedMaxWidth(for: splitView))
        }

        private func clampedMaxWidth(for splitView: NSSplitView) -> CGFloat {
            let detailMinimumWidth: CGFloat = 360
            let availableMax = max(parent.minWidth, splitView.bounds.width - detailMinimumWidth)
            return min(parent.maxWidth, availableMax)
        }
    }
}
