import SpriteKit

/// A drag-to-scroll vertical container.
///
/// SpriteKit has no scroll view, so this clips content with an `SKCropNode` and
/// translates it with touch deltas, adding rubber-banding at the edges and a
/// small inertial glide on release.
final class ScrollContainer: SKNode {

    private let crop = SKCropNode()
    private let content = SKNode()
    private let viewportSize: CGSize
    private let scrollbar = SKShapeNode()

    private var contentHeight: CGFloat = 0
    private var lastTouchY: CGFloat?
    private var lastTouchTime: TimeInterval = 0
    private var velocity: CGFloat = 0

    /// Extra travel allowed past the ends before snapping back.
    private let overscroll: CGFloat = 60

    init(size: CGSize) {
        self.viewportSize = size
        super.init()

        isUserInteractionEnabled = true

        let mask = SKSpriteNode(color: .white, size: size)
        crop.maskNode = mask
        crop.addChild(content)
        addChild(crop)

        scrollbar.strokeColor = .clear
        scrollbar.fillColor = SKColor(white: 1, alpha: 0.18)
        addChild(scrollbar)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Replace the contents.
    ///
    /// - Parameters:
    ///   - rows: nodes laid out top-to-bottom.
    ///   - rowHeight: vertical pitch between rows.
    func setRows(_ rows: [SKNode], rowHeight: CGFloat) {
        content.removeAllChildren()
        content.position = .zero

        var y = viewportSize.height / 2 - rowHeight / 2
        for row in rows {
            row.position = CGPoint(x: row.position.x, y: y)
            content.addChild(row)
            y -= rowHeight
        }

        contentHeight = CGFloat(rows.count) * rowHeight
        updateScrollbar()
    }

    /// How far the content can travel before hitting the bottom.
    private var maxOffset: CGFloat {
        max(0, contentHeight - viewportSize.height)
    }

    private func updateScrollbar() {
        guard maxOffset > 0 else {
            scrollbar.path = nil
            return
        }

        let trackHeight = viewportSize.height
        let thumbHeight = max(28, trackHeight * (viewportSize.height / contentHeight))
        let progress = min(1, max(0, content.position.y / maxOffset))
        let thumbY = trackHeight / 2 - thumbHeight / 2 - progress * (trackHeight - thumbHeight)

        let rect = CGRect(
            x: viewportSize.width / 2 - 3,
            y: thumbY - thumbHeight / 2,
            width: 3,
            height: thumbHeight
        )
        scrollbar.path = CGPath(roundedRect: rect, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        content.removeAction(forKey: "glide")
        lastTouchY = touch.location(in: self).y
        lastTouchTime = touch.timestamp
        velocity = 0
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let previous = lastTouchY, maxOffset > 0 else { return }
        let current = touch.location(in: self).y
        let delta = current - previous
        lastTouchY = current

        let interval = touch.timestamp - lastTouchTime
        if interval > 0 { velocity = delta / CGFloat(interval) }
        lastTouchTime = touch.timestamp

        // Resist movement past the ends so the limits are obvious.
        var next = content.position.y + delta
        if next < 0 {
            next = content.position.y + delta * 0.35
        } else if next > maxOffset {
            next = content.position.y + delta * 0.35
        }
        content.position.y = max(-overscroll, min(maxOffset + overscroll, next))
        updateScrollbar()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastTouchY = nil
        settle()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastTouchY = nil
        settle()
    }

    /// Glide with the release velocity, then snap back inside the bounds.
    private func settle() {
        guard maxOffset > 0 else {
            content.run(.moveTo(y: 0, duration: 0.2))
            return
        }

        let projected = content.position.y + velocity * 0.12
        let target = max(0, min(maxOffset, projected))
        let duration = min(0.45, max(0.12, abs(target - content.position.y) / 1_400))

        let glide = SKAction.moveTo(y: target, duration: duration)
        glide.timingMode = .easeOut
        // `run(_:withKey:)` has no completion overload, so the scrollbar update
        // is appended to the sequence instead.
        let update = SKAction.run { [weak self] in self?.updateScrollbar() }
        content.run(.sequence([glide, update]), withKey: "glide")
    }
}
