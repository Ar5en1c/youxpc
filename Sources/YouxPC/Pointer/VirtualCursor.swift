// VirtualCursor.swift - The agent's own on-screen pointer
//
// A small click-through overlay window that shows where the agent is acting.
// It is purely visual: it never posts input and never touches the user's real
// pointer. Actions glide it to their target and pulse it on click, so a person
// watching can follow the agent while keeping their own mouse.
//
// The MCP server blocks the main thread on stdin, so there is no run loop
// spinning between tool calls. Movement is therefore stepped manually (see
// `pump`), short effects are handed to Core Animation (they play in the render
// server without a run loop), and idle fade-out is driven by `idleTick()`,
// which MCPServer calls while it waits for input.
//
// Disable with YOUXPC_CURSOR=off.

import AppKit
import QuartzCore

/// The agent's visual pointer. All coordinates are global CoreGraphics points
/// (origin top-left of the primary display), matching AX frames and CGEvents.
public final class VirtualCursor {

    public static let shared = VirtualCursor()

    /// Whether the overlay is shown at all. Read once from the environment.
    public static let isEnabled: Bool = {
        let value = ProcessInfo.processInfo.environment["YOUXPC_CURSOR"]?.lowercased()
        return !["off", "0", "false", "no"].contains(value ?? "")
    }()

    private enum Visibility {
        case hidden
        case visible
        case fading(since: Date)
    }

    /// Side of the square overlay window. The pointer tip sits at its center so
    /// the click ring can expand around it without clipping.
    private static let canvas: CGFloat = 96
    private static let idleBeforeFade: TimeInterval = 3.0
    private static let fadeDuration: TimeInterval = 0.35

    private var window: NSWindow?
    private var pointerLayer: CAShapeLayer?
    private var ringLayer: CAShapeLayer?
    private var visibility: Visibility = .hidden
    private var tip: CGPoint?
    private var lastActivity = Date()

    private init() {}

    // MARK: - Public API

    /// Glide the pointer to a screen point, showing it first if needed.
    /// Blocks for the length of the animation (120-450 ms depending on distance).
    public func glide(to target: CGPoint) {
        guard Self.isEnabled, ensureWindow() else { return }

        let start = tip ?? CGEvent(source: nil)?.location ?? target
        show(at: start)

        let distance = hypot(target.x - start.x, target.y - start.y)
        if distance > 1 {
            let duration = min(0.45, max(0.12, Double(distance) / 2400))
            let began = CACurrentMediaTime()
            while true {
                let progress = min(1, (CACurrentMediaTime() - began) / duration)
                let eased = Self.easeInOut(progress)
                place(at: CGPoint(
                    x: start.x + (target.x - start.x) * eased,
                    y: start.y + (target.y - start.y) * eased
                ))
                pump(1.0 / 120)
                if progress >= 1 { break }
            }
        }
        place(at: target)
        CATransaction.flush()
        tip = target
        lastActivity = Date()
    }

    /// Play the click effect at the current position. Returns immediately;
    /// the animation runs in the render server.
    public func pulse() {
        guard Self.isEnabled, window != nil, let ringLayer, let pointerLayer else { return }

        CATransaction.begin()
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.35
        grow.toValue = 1.0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0.0
        let ring = CAAnimationGroup()
        ring.animations = [grow, fade]
        ring.duration = 0.32
        ring.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ringLayer.add(ring, forKey: "pulse")

        let press = CAKeyframeAnimation(keyPath: "transform.scale")
        press.values = [1.0, 0.82, 1.0]
        press.keyTimes = [0, 0.35, 1]
        press.duration = 0.2
        pointerLayer.add(press, forKey: "press")
        CATransaction.commit()
        CATransaction.flush()
        lastActivity = Date()
    }

    /// Jump the pointer to a point without animating. For callers that already
    /// step through a path themselves, such as a drag.
    public func track(_ point: CGPoint) {
        guard Self.isEnabled, ensureWindow() else { return }
        show(at: point)
        CATransaction.flush()
        tip = point
        lastActivity = Date()
    }

    /// Called by the MCP server while it waits for the next message. Fades the
    /// pointer out after a few idle seconds and removes the window afterwards.
    public func idleTick() {
        guard Self.isEnabled, let window else { return }
        switch visibility {
        case .hidden:
            return
        case .visible:
            guard Date().timeIntervalSince(lastActivity) > Self.idleBeforeFade else { return }
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = Self.fadeDuration
            window.animator().alphaValue = 0
            NSAnimationContext.endGrouping()
            visibility = .fading(since: Date())
            pump(0)
        case let .fading(since):
            pump(0)
            guard Date().timeIntervalSince(since) > Self.fadeDuration + 0.05 else { return }
            window.orderOut(nil)
            visibility = .hidden
        }
    }

    /// Remove the pointer immediately.
    public func hide() {
        window?.orderOut(nil)
        visibility = .hidden
    }

    // MARK: - Window

    private func ensureWindow() -> Bool {
        if window != nil { return true }
        guard !NSScreen.screens.isEmpty else { return false }

        // Accessory: no Dock icon, no menu bar, never becomes the active app.
        let app = NSApplication.shared
        if app.activationPolicy() != .accessory {
            app.setActivationPolicy(.accessory)
        }

        let side = Self.canvas
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: side, height: side),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.alphaValue = 0

        let view = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        view.wantsLayer = true
        panel.contentView = view
        guard let root = view.layer else { return false }

        let center = CGPoint(x: side / 2, y: side / 2)

        let ring = CAShapeLayer()
        let ringRadius: CGFloat = 26
        ring.bounds = CGRect(x: 0, y: 0, width: ringRadius * 2, height: ringRadius * 2)
        ring.position = center
        ring.path = CGPath(ellipseIn: ring.bounds.insetBy(dx: 2, dy: 2), transform: nil)
        ring.fillColor = Self.accent.withAlphaComponent(0.18).cgColor
        ring.strokeColor = Self.accent.cgColor
        ring.lineWidth = 2.5
        ring.opacity = 0
        root.addSublayer(ring)

        let pointer = CAShapeLayer()
        pointer.path = Self.arrowPath()
        pointer.fillColor = Self.accent.cgColor
        pointer.strokeColor = NSColor.white.cgColor
        pointer.lineWidth = 1.6
        pointer.lineJoin = .round
        pointer.shadowColor = NSColor.black.cgColor
        pointer.shadowOpacity = 0.35
        pointer.shadowRadius = 3
        pointer.shadowOffset = CGSize(width: 0, height: -1.5)
        // The arrow's tip is its local origin; anchor it at the window center.
        pointer.position = center
        root.addSublayer(pointer)

        window = panel
        ringLayer = ring
        pointerLayer = pointer
        return true
    }

    private func show(at point: CGPoint) {
        guard let window else { return }
        place(at: point)
        if case .visible = visibility {
            return
        }
        window.alphaValue = 1
        window.orderFrontRegardless()
        visibility = .visible
        CATransaction.flush()
    }

    /// Move the window so the pointer tip sits at `point`.
    private func place(at point: CGPoint) {
        guard let window, let primary = NSScreen.screens.first else { return }
        // CoreGraphics global space is top-left origin; AppKit is bottom-left.
        let half = Self.canvas / 2
        let cocoaY = primary.frame.height - point.y
        window.setFrameOrigin(NSPoint(x: point.x - half, y: cocoaY - half))
    }

    /// Let AppKit and Core Animation commit, then wait out the frame interval.
    private func pump(_ interval: TimeInterval) {
        CATransaction.flush()
        let deadline = Date().addingTimeInterval(interval)
        _ = RunLoop.current.run(mode: .default, before: deadline)
        let remaining = deadline.timeIntervalSinceNow
        if remaining > 0 {
            Thread.sleep(forTimeInterval: remaining)
        }
    }

    // MARK: - Drawing

    private static let accent = NSColor(srgbRed: 0.49, green: 0.36, blue: 1.0, alpha: 1.0)

    /// Classic arrow with its tip at the origin, drawn for a y-up layer.
    private static func arrowPath() -> CGPath {
        let scale: CGFloat = 1.3
        let outline: [(CGFloat, CGFloat)] = [
            (0, 0), (0, 17), (4.6, 13.2), (7.8, 20.5),
            (10.6, 19.3), (7.5, 12.2), (13, 12.2),
        ]
        let path = CGMutablePath()
        for (index, vertex) in outline.enumerated() {
            let point = CGPoint(x: vertex.0 * scale, y: -vertex.1 * scale)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}
