import SpriteKit

/// A titled card used by every overlay and menu section.
class PanelNode: SKNode {

    let size: CGSize
    private let background: SKShapeNode
    private var titleLabel: SKLabelNode?

    /// y coordinate just under the title, where content should start.
    var contentTop: CGFloat {
        titleLabel == nil ? size.height / 2 - 18 : size.height / 2 - 52
    }

    init(size: CGSize, title: String? = nil, titleColor: SKColor = Palette.accent) {
        self.size = size

        background = SKShapeNode(rectOf: size, cornerRadius: 18)
        background.fillColor = Palette.panel
        background.strokeColor = Palette.panelBorder
        background.lineWidth = 2.5

        super.init()
        addChild(background)

        if let title {
            let label = SKLabelNode(fontNamed: Fonts.display)
            label.text = title
            label.fontSize = 26
            label.fontColor = titleColor
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: 0, y: size.height / 2 - 30)
            addChild(label)
            titleLabel = label
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Fade + scale in. Overlays feel abrupt without it.
    func present(animated: Bool = true) {
        guard animated else { return }
        setScale(0.86)
        alpha = 0
        run(.group([
            .fadeIn(withDuration: 0.16),
            .scale(to: 1.0, duration: 0.22),
        ]))
    }

    /// A left-aligned label/value row, ready to be positioned by the caller.
    static func statRow(
        label: String,
        value: String,
        width: CGFloat,
        fontSize: CGFloat = 16,
        valueColor: SKColor = Palette.primaryText
    ) -> SKNode {
        let row = SKNode()

        let name = SKLabelNode(fontNamed: Fonts.body)
        name.text = label
        name.fontSize = fontSize
        name.fontColor = Palette.secondaryText
        name.horizontalAlignmentMode = .left
        name.verticalAlignmentMode = .center
        name.position = CGPoint(x: -width / 2, y: 0)
        row.addChild(name)

        let result = SKLabelNode(fontNamed: Fonts.display)
        result.text = value
        result.fontSize = fontSize + 2
        result.fontColor = valueColor
        result.horizontalAlignmentMode = .right
        result.verticalAlignmentMode = .center
        result.position = CGPoint(x: width / 2, y: 0)
        row.addChild(result)

        return row
    }
}

/// Transient message shown at the top of the screen.
///
/// Toasts queue rather than overlap, so a run that unlocks three achievements at
/// once shows all three in sequence.
final class ToastPresenter {

    private weak var container: SKNode?
    private let sceneSize: CGSize
    private var queue: [(text: String, color: SKColor)] = []
    private var isPresenting = false

    init(container: SKNode, sceneSize: CGSize) {
        self.container = container
        self.sceneSize = sceneSize
    }

    func show(_ text: String, color: SKColor = Palette.accent) {
        queue.append((text, color))
        presentNextIfIdle()
    }

    private func presentNextIfIdle() {
        guard !isPresenting, !queue.isEmpty, let container else { return }
        isPresenting = true
        let item = queue.removeFirst()

        let label = SKLabelNode(fontNamed: Fonts.display)
        label.text = item.text
        label.fontSize = 18
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center

        let padding: CGFloat = 18
        let width = min(sceneSize.width - 40, label.frame.width + padding * 2)
        let background = SKShapeNode(rectOf: CGSize(width: width, height: 40), cornerRadius: 20)
        background.fillColor = item.color.withAlphaComponent(0.92)
        background.strokeColor = .clear

        let toast = SKNode()
        toast.zPosition = ZPosition.toast
        toast.addChild(background)
        toast.addChild(label)
        toast.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height + 40)
        toast.alpha = 0
        container.addChild(toast)

        let targetY = sceneSize.height - 96
        toast.run(.sequence([
            .group([
                .fadeIn(withDuration: 0.18),
                .move(to: CGPoint(x: sceneSize.width / 2, y: targetY), duration: 0.24),
            ]),
            .wait(forDuration: GameConfig.toastDuration),
            .group([
                .fadeOut(withDuration: 0.25),
                .moveBy(x: 0, y: 30, duration: 0.25),
            ]),
            .removeFromParent(),
        ])) { [weak self] in
            self?.isPresenting = false
            self?.presentNextIfIdle()
        }
    }
}
