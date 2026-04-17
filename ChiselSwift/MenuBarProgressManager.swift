import AppKit

@MainActor
final class MenuBarProgressManager {
    static let shared = MenuBarProgressManager()
    
    private var statusItem: NSStatusItem?
    
    func show() {
        print("SHOWING MENU BAR PROGRESS INDICATOR")
        guard statusItem == nil else { return }
        
        // allocate a fixed space in the macos menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: 28)
        
        let indicator = NSProgressIndicator(frame: NSRect(x: 6, y: 4, width: 16, height: 16))
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.startAnimation(nil)
        
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 28, height: 24))
        containerView.addSubview(indicator)
        
        if let button = statusItem?.button {
            // Remove any previous subviews
            button.subviews.forEach { $0.removeFromSuperview() }
            containerView.frame = button.bounds
            button.addSubview(containerView)
        }
    }
    
    func hide() {
        print("HIDING MENU BAR PROGRESS INDICATOR")
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}
