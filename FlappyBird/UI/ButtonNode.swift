import SpriteKit

/// A tappable button.
///
/// SpriteKit has no button primitive, so this wraps the usual rounded-rect +
/// label + hit-test + press animation once instead of in every scene.
final class ButtonNode: SKNode {

    private let background: SKShapeNode
    private let label: SKLabelNode
    private let action: () -> Void
    private var isPressed = false

    /// Larger than the visual bounds so small buttons stay comfortably tappable.
    private let touchInset: CGFloat = -8

    let size: CGSize

    init(
        title: String,
        size: CGSize = CGSize(width: 220, height: 52),
        fontSize: CGFloat = 22,
        fillColor: SKColor = Palette.buttonFill,
        borderColor: SKColor = Palette.panelBorder,
        textColor: SKColor = Palette.primaryText,
        action: @escaping () -> Void
    ) {
        self.size = size
        self.action = action

        background = SKShapeNode(rectOf: size, cornerRadius: 12)
        background.fillColor = fillColor
        background.strokeColor = borderColor
        background.lineWidth = 2

        label = SKLabelNode(fontNamed: Fonts.display)
        label.text = title
        label.fontSize = fontSize
        label.fontColor = textColor
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center

        super.init()

        isUserInteractionEnabled = true
        addChild(background)
        addChild(label)

        // VoiceOver support: the node reads as a button with its title.
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var title: String {
        get { label.text ?? "" }
        set {
            label.text = newValue
            accessibilityLabel = newValue
        }
    }

    func setEnabled(_ enabled: Bool) {
        isUserInteractionEnabled = enabled
        alpha = enabled ? 1 : 0.45
    }

    func setHighlighted(_ highlighted: Bool) {
        background.fillColor = highlighted ? Palette.buttonFillActive : Palette.buttonFill
        background.lineWidth = highlighted ? 3 : 2
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isUserInteractionEnabled else { return }
        isPressed = true
        background.fillColor = Palette.buttonFillActive
        run(.scale(to: 0.96, duration: 0.06))
        Haptics.shared.buttonTap()
        AudioManager.shared.play(.uiTap)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isPressed else { return }
        isPressed = false
        background.fillColor = Palette.buttonFill
        run(.scale(to: 1.0, duration: 0.08))

        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        if background.frame.insetBy(dx: touchInset, dy: touchInset).contains(location) {
            action()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isPressed = false
        background.fillColor = Palette.buttonFill
        run(.scale(to: 1.0, duration: 0.08))
    }
}

/// A two-state settings row: label on the left, ON/OFF pill on the right.
final class ToggleRowNode: SKNode {

    private let label: SKLabelNode
    private let valueLabel: SKLabelNode
    private let background: SKShapeNode
    private let onChange: (Bool) -> Void
    private(set) var isOn: Bool

    let size: CGSize

    init(
        title: String,
        isOn: Bool,
        width: CGFloat = 300,
        onChange: @escaping (Bool) -> Void
    ) {
        self.isOn = isOn
        self.onChange = onChange
        self.size = CGSize(width: width, height: 44)

        background = SKShapeNode(rectOf: size, cornerRadius: 10)
        background.fillColor = Palette.buttonFill
        background.strokeColor = SKColor(white: 1, alpha: 0.12)
        background.lineWidth = 1

        label = SKLabelNode(fontNamed: Fonts.body)
        label.text = title
        label.fontSize = 16
        label.fontColor = Palette.primaryText
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: -width / 2 + 16, y: 0)

        valueLabel = SKLabelNode(fontNamed: Fonts.display)
        valueLabel.fontSize = 17
        valueLabel.horizontalAlignmentMode = .right
        valueLabel.verticalAlignmentMode = .center
        valueLabel.position = CGPoint(x: width / 2 - 16, y: 0)

        super.init()
        isUserInteractionEnabled = true
        addChild(background)
        addChild(label)
        addChild(valueLabel)
        refresh()

        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func refresh() {
        valueLabel.text = isOn ? "ON" : "OFF"
        valueLabel.fontColor = isOn ? Palette.positive : Palette.secondaryText
        accessibilityValue = isOn ? "on" : "off"
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isOn.toggle()
        refresh()
        Haptics.shared.buttonTap()
        AudioManager.shared.play(.uiTap)
        onChange(isOn)
    }
}
