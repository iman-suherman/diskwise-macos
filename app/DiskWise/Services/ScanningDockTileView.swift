import AppKit
import SwiftUI

final class ScanningDockTileView: NSView {
    private let baseImage: NSImage
    private let ringImage: NSImage?
    private let updatesDockTile: Bool
    private let imageInsetFraction: CGFloat
    private var animationTimer: Timer?
    private var rotationAngle: CGFloat = 0
    private var scanBeamPhase: CGFloat = 0

    var progressFraction: Double = 0
    var progressLabel = ""

    var statusDescription = "" {
        didSet {
            toolTip = statusDescription.isEmpty ? nil : statusDescription
            setAccessibilityLabel(statusDescription)
        }
    }

    init(
        baseImage: NSImage,
        ringImage: NSImage? = nil,
        size: NSSize? = nil,
        updatesDockTile: Bool = true,
        imageInsetFraction: CGFloat = 0
    ) {
        self.baseImage = baseImage
        self.ringImage = ringImage
        self.updatesDockTile = updatesDockTile
        self.imageInsetFraction = imageInsetFraction
        let resolvedSize = size ?? NSApp.dockTile.size
        super.init(frame: NSRect(origin: .zero, size: resolvedSize))
    }

    static func loadLayeredScanningImages() -> (base: NSImage, ring: NSImage?)? {
        let base = NSImage(named: "DockScanningBase")
            ?? NSImage(named: "DockScanning")
        guard let base else { return nil }
        let ring = NSImage(named: "DockScanningRing")
        return (base, ring)
    }

    static func loadScanningImage() -> NSImage? {
        if let layered = loadLayeredScanningImages() {
            return layered.base
        }
        if let url = Bundle.main.url(forResource: "scanning", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        animationTimer?.invalidate()
    }

    func startAnimating() {
        guard animationTimer == nil else { return }

        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.rotationAngle += .pi / 36
            if self.rotationAngle >= .pi * 2 {
                self.rotationAngle -= .pi * 2
            }
            self.scanBeamPhase += 0.035
            if self.scanBeamPhase >= 1 {
                self.scanBeamPhase = 0
            }
            self.needsDisplay = true
            if self.updatesDockTile {
                NSApp.dockTile.display()
            }
        }
        if let animationTimer {
            RunLoop.main.add(animationTimer, forMode: .common)
        }
    }

    func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let cornerRadius = bounds.width * 0.2237
        let clipPath = NSBezierPath(
            roundedRect: bounds,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        clipPath.addClip()

        let inset = bounds.width * imageInsetFraction
        let imageRect = bounds.insetBy(dx: inset, dy: inset)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        baseImage.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        drawScanBeam(in: imageRect, context: context)

        if let ringImage {
            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: rotationAngle)
            context.translateBy(x: -center.x, y: -center.y)
            ringImage.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            context.restoreGState()
        } else {
            drawFallbackRing(in: bounds, center: center, context: context)
        }

        if progressFraction > 0.05, !progressLabel.isEmpty, progressLabel != "0%" {
            drawProgressBadge(progressLabel, in: bounds)
        }
    }

    private func drawScanBeam(in imageRect: NSRect, context: CGContext) {
        let beamCenterY = imageRect.minY + imageRect.height * (0.24 + 0.46 * scanBeamPhase)
        let beamHeight = max(2, imageRect.height * 0.028)
        let beamRect = CGRect(
            x: imageRect.minX + imageRect.width * 0.14,
            y: beamCenterY - beamHeight / 2,
            width: imageRect.width * 0.72,
            height: beamHeight
        )

        context.saveGState()
        context.setShadow(offset: .zero, blur: beamHeight * 1.4, color: NSColor(
            calibratedRed: 0.0,
            green: 0.9,
            blue: 1.0,
            alpha: 0.55
        ).cgColor)
        context.setFillColor(NSColor(
            calibratedRed: 0.55,
            green: 0.95,
            blue: 1.0,
            alpha: 0.92
        ).cgColor)
        context.fill(beamRect)
        context.restoreGState()
    }

    private func drawFallbackRing(in bounds: NSRect, center: CGPoint, context: CGContext) {
        let ringRadius = bounds.width * 0.44
        let lineWidth = max(1.5, bounds.width * 0.022)
        let dashLength = bounds.width * 0.045
        let dashGap = bounds.width * 0.03
        context.saveGState()
        context.setStrokeColor(NSColor(
            calibratedRed: 0.145,
            green: 0.35,
            blue: 0.71,
            alpha: 0.85
        ).cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineDash(phase: rotationAngle * ringRadius, lengths: [dashLength, dashGap])
        context.addArc(
            center: center,
            radius: ringRadius,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: false
        )
        context.strokePath()
        context.restoreGState()
    }

    private func drawProgressBadge(_ label: String, in bounds: NSRect) {
        let fontSize = max(9, bounds.width * 0.14)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (label as NSString).size(withAttributes: attributes)
        let horizontalPadding = bounds.width * 0.06
        let verticalPadding = bounds.width * 0.03
        let badgeSize = NSSize(
            width: textSize.width + horizontalPadding * 2,
            height: textSize.height + verticalPadding * 2
        )
        let badgeOrigin = NSPoint(
            x: bounds.maxX - badgeSize.width - bounds.width * 0.04,
            y: bounds.minY + bounds.width * 0.04
        )
        let badgeRect = NSRect(origin: badgeOrigin, size: badgeSize)
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: badgeSize.height / 2, yRadius: badgeSize.height / 2)
        NSColor.black.withAlphaComponent(0.55).setFill()
        badgePath.fill()

        let textOrigin = NSPoint(
            x: badgeRect.midX - textSize.width / 2,
            y: badgeRect.midY - textSize.height / 2
        )
        (label as NSString).draw(at: textOrigin, withAttributes: attributes)
    }
}

struct ScanningDockTileRepresentable: NSViewRepresentable {
    var size: CGFloat = 88
    var progressFraction: Double = 0
    var progressLabel = ""
    var statusDescription = ""

    func makeNSView(context: Context) -> ScanningDockTileView {
        let layered = ScanningDockTileView.loadLayeredScanningImages()
        let baseImage = layered?.base
            ?? NSApp.applicationIconImage
            ?? NSImage(systemSymbolName: "externaldrive.fill", accessibilityDescription: nil)!
        let view = ScanningDockTileView(
            baseImage: baseImage,
            ringImage: layered?.ring,
            size: NSSize(width: size, height: size),
            updatesDockTile: false
        )
        view.progressFraction = progressFraction
        view.progressLabel = progressLabel
        view.statusDescription = statusDescription
        view.startAnimating()
        return view
    }

    func updateNSView(_ nsView: ScanningDockTileView, context: Context) {
        nsView.progressFraction = progressFraction
        nsView.progressLabel = progressLabel
        nsView.statusDescription = statusDescription
        nsView.needsDisplay = true
    }

    static func dismantleNSView(_ nsView: ScanningDockTileView, coordinator: ()) {
        nsView.stopAnimating()
    }
}
