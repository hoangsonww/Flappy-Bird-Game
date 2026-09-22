import SpriteKit

/// A small drawn coin, used wherever the wallet is shown.
///
/// Drawing it keeps the HUD, menu and shop consistent with the coins that spawn
/// in the world — and avoids the platform emoji, which renders as a silver disc
/// and reads as "off" next to the gold in-game pickups.
enum CoinIcon {

    static func node(radius: CGFloat = 8) -> SKNode {
        let coin = SKShapeNode(circleOfRadius: radius)
        coin.fillColor = SKColor(red: 0.99, green: 0.82, blue: 0.28, alpha: 1)
        coin.strokeColor = SKColor(red: 0.72, green: 0.52, blue: 0.09, alpha: 1)
        coin.lineWidth = max(1, radius * 0.18)

        let highlight = SKShapeNode(circleOfRadius: radius * 0.45)
        highlight.fillColor = SKColor(red: 1.0, green: 0.94, blue: 0.68, alpha: 1)
        highlight.strokeColor = .clear
        coin.addChild(highlight)

        return coin
    }

    /// Coin icon followed by a right-growing amount label.
    ///
    /// - Returns: a node anchored at the coin's centre, plus the label so the
    ///   caller can update the amount without rebuilding the icon.
    static func counter(
        amount: Int,
        radius: CGFloat = 8,
        fontSize: CGFloat = 18,
        color: SKColor = SKColor(red: 0.99, green: 0.82, blue: 0.28, alpha: 1)
    ) -> (node: SKNode, label: SKLabelNode) {
        let container = SKNode()
        container.addChild(node(radius: radius))

        let label = SKLabelNode(fontNamed: Fonts.display)
        label.text = String(amount)
        label.fontSize = fontSize
        label.fontColor = color
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: radius + 8, y: 0)
        container.addChild(label)

        return (container, label)
    }
}

/// Text helpers shared by the list rows.
enum TextFit {

    /// Shorten `text` with an ellipsis until it fits `maxWidth` at the given font.
    ///
    /// SpriteKit labels do not truncate, so without this a long subtitle simply
    /// runs underneath the value on the right-hand side of a row.
    static func truncate(
        _ text: String,
        toWidth maxWidth: CGFloat,
        fontNamed fontName: String,
        fontSize: CGFloat
    ) -> String {
        guard maxWidth > 0 else { return "" }

        let probe = SKLabelNode(fontNamed: fontName)
        probe.fontSize = fontSize
        probe.text = text
        if probe.frame.width <= maxWidth { return text }

        var characters = Array(text)
        while characters.count > 1 {
            characters.removeLast()
            probe.text = String(characters) + "…"
            if probe.frame.width <= maxWidth { return probe.text ?? text }
        }
        return "…"
    }
}
