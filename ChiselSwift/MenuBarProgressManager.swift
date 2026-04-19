import AppKit

@MainActor
final class MenuBarProgressManager {
    static let shared = MenuBarProgressManager()

    private var statusItem: NSStatusItem?
    private var indicator: NSProgressIndicator?

    // isDeterminate = false for background intent, true for foreground ui
    func show(isDeterminate: Bool = false) {
        guard statusItem == nil else { return }
        print("SHOWING MENU BAR PROGRESS INDICATOR")

        // allocate a fixed space in the macos menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: 28)

        let newIndicator = NSProgressIndicator(frame: NSRect(x: 6, y: 4, width: 16, height: 16))
        newIndicator.style = .spinning
        newIndicator.controlSize = .small
        newIndicator.isIndeterminate = !isDeterminate

        if isDeterminate {
            newIndicator.minValue = 0
            newIndicator.maxValue = 100
            newIndicator.doubleValue = 0
        } else {
            newIndicator.startAnimation(nil)
        }

        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 24))
        containerView.addSubview(newIndicator)

        if let button = statusItem?.button {
            // Remove any previous subviews
            button.subviews.forEach { $0.removeFromSuperview() }
            containerView.frame = button.bounds
            button.addSubview(containerView)
        }

        self.indicator = newIndicator
    }

    func updateProgress(_ percentage: Double) {
        // updates the pie chart fill level
        indicator?.doubleValue = percentage * 100
    }

    func hide() {
        print("HIDING MENU BAR PROGRESS INDICATOR")
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            indicator = nil
        }
    }
}

import SwiftUI

#if DEBUG
// wrapper to expose appkit views to swiftui canvas
struct MenuBarWidgetPreview: NSViewRepresentable {
    let isDeterminate: Bool
    let percentage: Double

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 24))

        let indicator = NSProgressIndicator(frame: NSRect(x: 6, y: 4, width: 16, height: 16))
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.isIndeterminate = !isDeterminate

        if isDeterminate {
            indicator.minValue = 0
            indicator.maxValue = 100
            indicator.doubleValue = percentage * 100
        } else {
            indicator.startAnimation(nil)
        }

        containerView.addSubview(indicator)
        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // no dynamic updates needed for simple previews
    }
}

#Preview("MenuBar Widget States") {
    VStack(alignment: .leading, spacing: 20) {
        HStack {
            Text("Intent background (indeterminate):")
                .font(.caption)
                .frame(width: 220, alignment: .leading)
            MenuBarWidgetPreview(isDeterminate: false, percentage: 0)
                .frame(width: 28, height: 24)
                // simulate macos menubar height and padding
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(4)
        }

        HStack {
            Text("Foreground UI (30%):")
                .font(.caption)
                .frame(width: 220, alignment: .leading)
            MenuBarWidgetPreview(isDeterminate: true, percentage: 0.3)
                .frame(width: 28, height: 24)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(4)
        }

        HStack {
            Text("Foreground UI (85%):")
                .font(.caption)
                .frame(width: 220, alignment: .leading)
            MenuBarWidgetPreview(isDeterminate: true, percentage: 0.85)
                .frame(width: 28, height: 24)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(4)
        }
    }
    .padding()
    .frame(width: 350)
}
#endif
