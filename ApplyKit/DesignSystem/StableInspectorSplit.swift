//
//  StableInspectorSplit.swift
//  ApplyKit
//

import AppKit
import SwiftUI

/// Split view with a trailing inspector pane that slides in and out (Xcode-style)
/// and keeps a stable width while the content pane flexes with the window.
/// Counterpart to `StableSidebarSplit`, which persists the leading pane instead.
/// Built on `NSSplitViewController` so collapse animation and divider hiding
/// come from AppKit.
struct StableInspectorSplit<Content: View, Inspector: View>: NSViewControllerRepresentable {
    @Binding var inspectorWidth: CGFloat
    @Binding var isVisible: Bool
    var minWidth: CGFloat = 300
    var maxWidth: CGFloat = 560
    @ViewBuilder let content: Content
    @ViewBuilder let inspector: Inspector

    func makeNSViewController(context: Context) -> InspectorSplitViewController {
        let controller = InspectorSplitViewController(
            content: AnyView(content),
            inspector: AnyView(inspector),
            inspectorMinWidth: minWidth,
            inspectorMaxWidth: maxWidth,
            desiredInspectorWidth: inspectorWidth,
            isInspectorVisible: isVisible
        )
        wireCallbacks(controller)
        return controller
    }

    func updateNSViewController(_ controller: InspectorSplitViewController, context: Context) {
        controller.contentHost.rootView = AnyView(content)
        controller.inspectorHost.rootView = AnyView(inspector)
        wireCallbacks(controller)
        controller.updateDesiredInspectorWidth(inspectorWidth)
        controller.scheduleLayoutUpdate(isVisible: isVisible)
    }

    private func wireCallbacks(_ controller: InspectorSplitViewController) {
        controller.onInspectorWidthChange = { width in
            if abs(inspectorWidth - width) > 1 { inspectorWidth = width }
        }
        controller.onInspectorVisibilityChange = { visible in
            if isVisible != visible { isVisible = visible }
        }
    }
}

final class InspectorSplitViewController: NSSplitViewController {
    let contentHost: NSHostingController<AnyView>
    let inspectorHost: NSHostingController<AnyView>
    private(set) var desiredInspectorWidth: CGFloat
    var onInspectorWidthChange: ((CGFloat) -> Void)?
    var onInspectorVisibilityChange: ((Bool) -> Void)?

    private let inspectorItem: NSSplitViewItem
    private let inspectorMinWidth: CGFloat
    private let inspectorMaxWidth: CGFloat
    private var collapseObservation: NSKeyValueObservation?
    private var hasAppliedInitialWidth = false
    private var isAnimatingVisibility = false
    private var visibilityAnimationGeneration = 0
    private var pendingVisibility: Bool?
    private var isLayoutUpdateScheduled = false

    init(
        content: AnyView,
        inspector: AnyView,
        inspectorMinWidth: CGFloat,
        inspectorMaxWidth: CGFloat,
        desiredInspectorWidth: CGFloat,
        isInspectorVisible: Bool
    ) {
        contentHost = NSHostingController(rootView: content)
        inspectorHost = NSHostingController(rootView: inspector)
        self.inspectorMinWidth = inspectorMinWidth
        self.inspectorMaxWidth = inspectorMaxWidth
        let initialWidth = desiredInspectorWidth.isFinite ? desiredInspectorWidth : inspectorMinWidth
        self.desiredInspectorWidth = min(max(initialWidth, inspectorMinWidth), inspectorMaxWidth)

        let contentItem = NSSplitViewItem(viewController: contentHost)
        contentItem.minimumThickness = 500
        contentItem.holdingPriority = .defaultLow

        inspectorItem = NSSplitViewItem(inspectorWithViewController: inspectorHost)
        inspectorItem.minimumThickness = inspectorMinWidth
        inspectorItem.maximumThickness = inspectorMaxWidth
        inspectorItem.canCollapse = true
        inspectorItem.holdingPriority = NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.defaultLow.rawValue + 1)
        inspectorItem.isCollapsed = !isInspectorVisible

        super.init(nibName: nil, bundle: nil)

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        addSplitViewItem(contentItem)
        addSplitViewItem(inspectorItem)

        // Syncs drag-to-collapse (and any other AppKit-initiated collapse)
        // back into the SwiftUI binding.
        collapseObservation = inspectorItem.observe(\.isCollapsed) { [weak self] item, _ in
            guard let self, !self.isAnimatingVisibility else { return }
            self.onInspectorVisibilityChange?(!item.isCollapsed)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func updateDesiredInspectorWidth(_ width: CGFloat) {
        desiredInspectorWidth = clampedInspectorWidth(width)
    }

    /// AppKit layout changes must not run synchronously from
    /// `updateNSViewController`, while SwiftUI may be rendering a hosting view.
    func scheduleLayoutUpdate(isVisible: Bool) {
        pendingVisibility = isVisible
        guard !isLayoutUpdateScheduled else { return }
        isLayoutUpdateScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isLayoutUpdateScheduled = false
            guard let isVisible = self.pendingVisibility else { return }
            self.pendingVisibility = nil
            self.setInspectorVisible(isVisible, animated: true)
            self.applyDesiredWidthIfNeeded()
        }
    }

    func setInspectorVisible(_ visible: Bool, animated: Bool) {
        guard inspectorItem.isCollapsed == visible else { return }
        guard animated else {
            visibilityAnimationGeneration += 1
            isAnimatingVisibility = false
            inspectorItem.isCollapsed = !visible
            return
        }
        visibilityAnimationGeneration += 1
        let animationGeneration = visibilityAnimationGeneration
        isAnimatingVisibility = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            inspectorItem.animator().isCollapsed = !visible
        } completionHandler: { [weak self] in
            guard let self else { return }
            guard self.visibilityAnimationGeneration == animationGeneration else { return }
            self.isAnimatingVisibility = false
            self.onInspectorVisibilityChange?(!self.inspectorItem.isCollapsed)
            if visible { self.applyDesiredWidthIfNeeded() }
        }
    }

    /// Moves the divider so the inspector matches the desired width, unless it's
    /// collapsed, mid-animation, or already there.
    func applyDesiredWidthIfNeeded() {
        guard splitView.bounds.width > 0, !inspectorItem.isCollapsed, !isAnimatingVisibility else { return }
        let current = inspectorHost.view.frame.width
        let targetWidth = clampedInspectorWidth(desiredInspectorWidth)
        guard abs(current - targetWidth) > 1 else { return }
        splitView.setPosition(
            splitView.bounds.width - targetWidth - splitView.dividerThickness,
            ofDividerAt: 0
        )
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard !hasAppliedInitialWidth, splitView.bounds.width > 0 else { return }
        hasAppliedInitialWidth = true
        applyDesiredWidthIfNeeded()
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        // Since macOS 12, layout-driven notifications also carry a divider index.
        // The user-resize flag is the reliable way to avoid persisting transient
        // window-resize and collapse-animation widths.
        guard (notification.userInfo?["NSSplitViewUserResizeKey"] as? NSNumber)?.boolValue == true,
              !inspectorItem.isCollapsed,
              !isAnimatingVisibility else {
            return
        }
        let width = inspectorHost.view.frame.width
        guard width.isFinite, width >= inspectorMinWidth - 1 else { return }
        let clampedWidth = clampedInspectorWidth(width)
        if abs(desiredInspectorWidth - clampedWidth) > 1 {
            desiredInspectorWidth = clampedWidth
            onInspectorWidthChange?(clampedWidth)
        }
    }

    private func clampedInspectorWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite else { return inspectorMinWidth }
        return min(max(width, inspectorMinWidth), inspectorMaxWidth)
    }
}
