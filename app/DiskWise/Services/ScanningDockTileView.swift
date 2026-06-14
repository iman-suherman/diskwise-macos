import AppKit

final class ScanningDockTileView: NSView {
    private let scanningImage: NSImage
    private var animationTimer: Timer?
    private var rotationAngle: CGFloat = 0
    private var pulsePhase: CGFloat = 0

    var progressFraction: Double = 0
    var progressLabel = ""

    var statusDescription = "" {
        didSet {
            toolTip = statusDescription.isEmpty ? nil : statusDescription
            setAccessibilityLabel(statusDescription)
        }
    }

    init(image: NSImage) {
        scanningImage = image
        let size = NSApp.dockTile.size
        super.init(frame: NSRect(origin: .zero, size: size))
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
            self.rotationAngle += .pi / 45
            if self.rotationAngle >= .pi * 2 {
                self.rotationAngle -= .pi * 2
            }
            self.pulsePhase += 0.1
            self.needsDisplay = true
            NSApp.dockTile.display()
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
        NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).addClip()

        scanningImage.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let ringRadius = bounds.width * 0.44
        let lineWidth = max(1.5, bounds.width * 0.022)

        context.saveGState()
        context.setStrokeColor(NSColor(calibratedRed: 0.2, green: 0.78, blue: 1.0, alpha: 0.9).cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.addArc(
            center: center,
            radius: ringRadius,
            startAngle: rotationAngle - .pi / 2,
            endAngle: rotationAngle + .pi / 5 - .pi / 2,
            clockwise: false
        )
        context.strokePath()
        context.restoreGState()

        let dotAngle = rotationAngle - .pi / 2
        let pulse = 0.65 + 0.35 * sin(pulsePhase)
        let dotRadius = max(1.5, bounds.width * 0.028 * pulse)
        let dotCenter = CGPoint(
            x: center.x + ringRadius * cos(dotAngle),
            y: center.y + ringRadius * sin(dotAngle)
        )
        context.setFillColor(NSColor(calibratedRed: 0.35, green: 0.9, blue: 1.0, alpha: 0.95).cgColor)
        context.fillEllipse(in: CGRect(
            x: dotCenter.x - dotRadius,
            y: dotCenter.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        ))

        if progressFraction > 0.05, !progressLabel.isEmpty, progressLabel != "0%" {
            drawProgressBadge(progressLabel, in: bounds)
        }
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
