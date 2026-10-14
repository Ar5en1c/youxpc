// Annotate.swift - Set-of-Marks annotation for YouxPC v2
//
// Maps to MCP tool: pc_annotate
//
// Takes a screenshot, overlays numbered labels on interactive elements,
// returns the annotated image + text index. Zero ML — uses AX tree positions.

import AppKit
import AXorcist
import CoreGraphics
import CoreText
import Foundation

/// Set-of-Marks annotation: labeled screenshots for visual agent workflows.
public enum Annotate {

    /// Default interactive roles to label.
    private static let defaultRoles: Set<String> = [
        "AXButton", "AXLink", "AXTextField", "AXTextArea",
        "AXCheckBox", "AXRadioButton", "AXPopUpButton",
        "AXComboBox", "AXMenuButton", "AXTab", "AXSlider",
        "AXMenuItem", "AXSearchField",
    ]

    /// An interactive element with its screen-coordinate bounding box.
    private struct AnnotatableElement {
        let role: String
        let name: String
        let screenX: Double
        let screenY: Double
        let width: Double
        let height: Double

        var centerX: Double { screenX + width / 2 }
        var centerY: Double { screenY + height / 2 }
    }

    // MARK: - pc_annotate

    /// Annotate an app window with numbered labels on interactive elements.
    public static func annotate(
        appName: String?,
        roles: [String]?,
        maxLabels: Int?
    ) -> ToolResult {
        // Resolve app
        let targetApp: NSRunningApplication
        if let appName {
            guard let app = Perception.findApp(named: appName) else {
                return ToolResult(success: false, error: "Application '\(appName)' not found")
            }
            targetApp = app
        } else {
            guard let frontApp = NSWorkspace.shared.frontmostApplication else {
                return ToolResult(success: false, error: "No frontmost application")
            }
            targetApp = frontApp
        }

        let pid = targetApp.processIdentifier
        let appDisplayName = targetApp.localizedName ?? appName ?? "app"

        // Capture screenshot (always nominal resolution for manageable size)
        let (screenshotOpt, failure) = ScreenCapture.captureWindowSyncWithReason(
            pid: pid, fullResolution: false
        )

        // Retry with activation if needed (same pattern as Perception.screenshot)
        let screenshot: ScreenshotResult
        if let s = screenshotOpt {
            screenshot = s
        } else {
            if case .noPermission = failure {
                return ToolResult(
                    success: false,
                    error: "Screen Recording permission not granted",
                    suggestion: "Grant Screen Recording in System Settings > Privacy & Security > Screen Recording."
                )
            }
            if case .windowListUnavailable = failure {
                return ToolResult(success: false, error: "CGWindowListCopyWindowInfo returned nil")
            }

            Log.info("Annotate: retrying after focus for \(appDisplayName)")
            targetApp.activate()
            Thread.sleep(forTimeInterval: 0.5)

            let (retryResult, _) = ScreenCapture.captureWindowSyncWithReason(
                pid: pid, fullResolution: false
            )
            guard let r = retryResult else {
                return ToolResult(
                    success: false,
                    error: "Screenshot capture failed for '\(appDisplayName)'",
                    suggestion: "Ensure Screen Recording permission is granted."
                )
            }
            screenshot = r
        }

        // Collect interactive elements
        guard let appElement = Element.application(for: pid) else {
            return ToolResult(
                success: false,
                error: "Cannot access accessibility tree for '\(appDisplayName)'",
                suggestion: "Try pc_focus on the app first."
            )
        }

        appElement.setMessagingTimeout(3.0)
        defer { appElement.setMessagingTimeout(0) }

        let roleSet: Set<String>
        if let roles, !roles.isEmpty {
            roleSet = Set(roles)
        } else {
            roleSet = defaultRoles
        }

        let cap = min(maxLabels ?? 50, 100)

        let window = appElement.focusedWindow() ?? appElement.mainWindow()
        guard let window else {
            return ToolResult(success: false, error: "No window found for '\(appDisplayName)'")
        }

        var collected: [AnnotatableElement] = []
        collectElements(
            from: window,
            roles: roleSet,
            results: &collected,
            windowX: screenshot.windowX,
            windowY: screenshot.windowY,
            windowWidth: screenshot.windowWidth,
            windowHeight: screenshot.windowHeight,
            semanticDepth: 0,
            maxSemanticDepth: 15
        )

        // Deduplicate: same position (within 5px) and same role → keep first
        var deduped: [AnnotatableElement] = []
        for elem in collected {
            let dominated = deduped.contains { existing in
                abs(existing.screenX - elem.screenX) < 5 &&
                abs(existing.screenY - elem.screenY) < 5 &&
                existing.role == elem.role
            }
            if !dominated { deduped.append(elem) }
        }

        // Sort: top-to-bottom, then left-to-right
        deduped.sort { a, b in
            if abs(a.screenY - b.screenY) > 10 { return a.screenY < b.screenY }
            return a.screenX < b.screenX
        }

        let elements = Array(deduped.prefix(cap))
        Log.info("Annotate: \(elements.count) elements found for '\(appDisplayName)'")

        // Decode base64 PNG to raw data
        guard let pngData = Data(base64Encoded: screenshot.base64PNG) else {
            return ToolResult(success: false, error: "Failed to decode screenshot data")
        }

        // Draw annotations
        guard let annotatedPNG = drawAnnotations(
            on: pngData,
            imageWidth: screenshot.width,
            imageHeight: screenshot.height,
            elements: elements,
            windowX: screenshot.windowX,
            windowY: screenshot.windowY,
            windowWidth: screenshot.windowWidth,
            windowHeight: screenshot.windowHeight
        ) else {
            return ToolResult(success: false, error: "Failed to draw annotations")
        }

        let base64Annotated = annotatedPNG.base64EncodedString()
        let index = buildTextIndex(
            elements: elements,
            windowX: screenshot.windowX,
            windowY: screenshot.windowY,
            windowWidth: screenshot.windowWidth,
            windowHeight: screenshot.windowHeight
        )

        return ToolResult(
            success: true,
            data: [
                "annotated_image": base64Annotated,
                "mime_type": "image/png",
                "width": screenshot.width,
                "height": screenshot.height,
                "window_title": screenshot.windowTitle as Any,
                "element_count": elements.count,
                "index": index,
            ]
        )
    }

    // MARK: - Element Collection

    /// Layout roles that cost zero semantic depth.
    private static let layoutRoles: Set<String> = [
        "AXGroup", "AXGenericElement", "AXSection", "AXDiv",
        "AXList", "AXLandmarkMain", "AXLandmarkNavigation",
        "AXLandmarkBanner", "AXLandmarkContentInfo",
    ]

    private static func collectElements(
        from element: Element,
        roles: Set<String>,
        results: inout [AnnotatableElement],
        windowX: Double,
        windowY: Double,
        windowWidth: Double,
        windowHeight: Double,
        semanticDepth: Int,
        maxSemanticDepth: Int
    ) {
        // Over-collect (200) before dedup/sort, then truncate to maxLabels.
        // Dedup can remove 30-50% of elements, so we need headroom.
        guard semanticDepth <= maxSemanticDepth, results.count < 200 else { return }

        let role = element.role() ?? ""

        // Semantic depth tunneling: empty layout containers cost 0
        let hasContent: Bool
        if layoutRoles.contains(role) {
            let title = element.title()
            let desc = element.descriptionText()
            hasContent = title != nil || desc != nil
        } else {
            hasContent = true
        }
        let childDepth = hasContent ? semanticDepth + 1 : semanticDepth

        // Check if this element is one we want to annotate
        if roles.contains(role) {
            if let pos = element.position(), let size = element.size() {
                let x = Double(pos.x)
                let y = Double(pos.y)
                let w = Double(size.width)
                let h = Double(size.height)

                // Skip tiny elements and those outside window bounds
                let tolerance: Double = 5
                let inBounds = x + w > windowX - tolerance &&
                               x < windowX + windowWidth + tolerance &&
                               y + h > windowY - tolerance &&
                               y < windowY + windowHeight + tolerance

                if inBounds && w >= 8 && h >= 8 {
                    let name = element.computedName() ?? element.title() ?? ""
                    results.append(AnnotatableElement(
                        role: role, name: name,
                        screenX: x, screenY: y, width: w, height: h
                    ))
                }
            }
        }

        // Recurse
        guard let children = element.children() else { return }
        for child in children {
            collectElements(
                from: child, roles: roles, results: &results,
                windowX: windowX, windowY: windowY,
                windowWidth: windowWidth, windowHeight: windowHeight,
                semanticDepth: childDepth, maxSemanticDepth: maxSemanticDepth
            )
        }
    }

    // MARK: - Drawing

    private static func drawAnnotations(
        on pngData: Data,
        imageWidth: Int,
        imageHeight: Int,
        elements: [AnnotatableElement],
        windowX: Double,
        windowY: Double,
        windowWidth: Double,
        windowHeight: Double
    ) -> Data? {
        guard let dataProvider = CGDataProvider(data: pngData as CFData),
              let sourceImage = CGImage(
                pngDataProviderSource: dataProvider,
                decode: nil, shouldInterpolate: true, intent: .defaultIntent
              )
        else {
            Log.error("Annotate: failed to decode PNG to CGImage")
            return nil
        }

        guard let context = CGContext(
            data: nil,
            width: imageWidth,
            height: imageHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            Log.error("Annotate: failed to create CGContext")
            return nil
        }

        // Draw the original screenshot
        context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

        // Guard against zero window dimensions
        guard windowWidth > 0, windowHeight > 0 else {
            Log.warn("Annotate: window dimensions are zero, returning unannotated image")
            guard let outImage = context.makeImage() else { return nil }
            let bitmap = NSBitmapImageRep(cgImage: outImage)
            return bitmap.representation(using: .png, properties: [:])
        }

        // Coordinate mapping: screen logical points → image pixels
        let scaleX = Double(imageWidth) / windowWidth
        let scaleY = Double(imageHeight) / windowHeight

        // Font for labels
        let fontSize: CGFloat = max(11.0 * CGFloat(scaleX), 9.0)
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)

        let red = CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        let white = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        let boxOutline = CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.7)

        for (index, elem) in elements.enumerated() {
            let label = "\(index + 1)"

            // Map element screen coords to image pixel coords
            let relX = (elem.screenX - windowX) * scaleX
            let relY = (elem.screenY - windowY) * scaleY
            let pixW = elem.width * scaleX
            let pixH = elem.height * scaleY

            // CGContext has origin at bottom-left, flip Y
            let flippedY = Double(imageHeight) - relY - pixH

            // Draw bounding box outline
            context.setStrokeColor(boxOutline)
            context.setLineWidth(1.5)
            context.stroke(CGRect(x: relX, y: flippedY, width: pixW, height: pixH))

            // Measure label text
            let attrString = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)!
            CFAttributedStringReplaceString(attrString, CFRangeMake(0, 0), label as CFString)
            CFAttributedStringSetAttribute(attrString, CFRangeMake(0, label.count), kCTFontAttributeName, font)
            CFAttributedStringSetAttribute(attrString, CFRangeMake(0, label.count), kCTForegroundColorAttributeName, white)

            let line = CTLineCreateWithAttributedString(attrString)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let textWidth = Double(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let textHeight = Double(ascent + descent)

            // Label pill position (top-left corner of element, in flipped coords)
            let padX: Double = 3.0
            let padY: Double = 2.0
            let pillW = textWidth + padX * 2
            let pillH = textHeight + padY * 2
            let pillX = relX + 2
            let pillY = flippedY + pixH - pillH - 2

            // Draw pill background
            let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: pillH)
            context.setFillColor(red)
            context.fill(pillRect)

            // Draw label text
            context.saveGState()
            context.textPosition = CGPoint(
                x: pillX + padX,
                y: pillY + padY + descent
            )
            CTLineDraw(line, context)
            context.restoreGState()
        }

        guard let annotatedImage = context.makeImage() else {
            Log.error("Annotate: failed to make image from context")
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: annotatedImage)
        return bitmap.representation(using: .png, properties: [:])
    }

    // MARK: - Text Index

    /// Build text index with click coordinates in screen space.
    /// Coordinates are clamped to the visible window bounds so elements
    /// with large virtual areas (e.g. terminal scrollback) get usable targets.
    private static func buildTextIndex(
        elements: [AnnotatableElement],
        windowX: Double,
        windowY: Double,
        windowWidth: Double,
        windowHeight: Double
    ) -> String {
        var lines: [String] = []
        lines.append("Elements found: \(elements.count)")
        lines.append("")

        for (index, elem) in elements.enumerated() {
            let n = index + 1
            let shortRole = elem.role.hasPrefix("AX") ? String(elem.role.dropFirst(2)) : elem.role
            let nameStr = elem.name.isEmpty ? "" : " \"\(elem.name)\""
            // Clamp center to visible window bounds (handles scrollback text areas)
            let cx = Int(min(max(elem.centerX, windowX), windowX + windowWidth))
            let cy = Int(min(max(elem.centerY, windowY), windowY + windowHeight))
            lines.append("[\(n)] \(shortRole)\(nameStr) — click: (\(cx), \(cy))")
        }

        lines.append("")
        lines.append("Use pc_click with x/y coordinates to click any labeled element.")

        return lines.joined(separator: "\n")
    }
}
