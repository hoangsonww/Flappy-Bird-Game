import SpriteKit

/// Shared chrome for every full-screen list: title, back button, scroll area and
/// a status line for empty/error states.
///
/// Subclasses override `buildContent()` and call `setRows(_:)`.
class ListScene: SKScene {

    private(set) var scroll: ScrollContainer!
    private(set) var statusLabel: SKLabelNode!
    private var headerLabel: SKLabelNode!
    private var segmentedButtons: [ButtonNode] = []

    /// Screen title. Override in subclasses.
    var screenTitle: String { "LIST" }
    /// Height of each row in the scroll area.
    var rowHeight: CGFloat { 44 }
    /// Optional filter chips rendered under the title.
    var segments: [String] { [] }
    private(set) var selectedSegment = max(0, LaunchOptions.initialSegment ?? 0)

    var contentWidth: CGFloat { min(size.width - 32, 360) }

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.05, green: 0.07, blue: 0.13, alpha: 1)

        buildHeader()
        buildScroll()
        buildContent()
    }

    // MARK: - Chrome

    private func buildHeader() {
        let topInset = view?.safeAreaInsets.top ?? 0

        headerLabel = SKLabelNode(fontNamed: Fonts.display)
        headerLabel.text = screenTitle
        headerLabel.fontSize = 26
        headerLabel.fontColor = Palette.accent
        headerLabel.horizontalAlignmentMode = .center
        headerLabel.position = CGPoint(x: size.width / 2, y: size.height - topInset - 46)
        addChild(headerLabel)

        let back = ButtonNode(title: "‹", size: CGSize(width: 44, height: 40), fontSize: 26) { [weak self] in
            self?.goBack()
        }
        back.position = CGPoint(x: 36, y: size.height - topInset - 40)
        addChild(back)

        guard !segments.isEmpty else { return }

        let width = min(contentWidth / CGFloat(segments.count) - 6, 110)
        let totalWidth = (width + 6) * CGFloat(segments.count) - 6

        for (index, title) in segments.enumerated() {
            let button = ButtonNode(
                title: title,
                size: CGSize(width: width, height: 32),
                fontSize: 12
            ) { [weak self] in
                self?.selectSegment(index)
            }
            button.position = CGPoint(
                x: size.width / 2 - totalWidth / 2 + width / 2 + CGFloat(index) * (width + 6),
                y: size.height - topInset - 86
            )
            button.setHighlighted(index == selectedSegment)
            addChild(button)
            segmentedButtons.append(button)
        }
    }

    private func buildScroll() {
        let topInset = view?.safeAreaInsets.top ?? 0
        let bottomInset = view?.safeAreaInsets.bottom ?? 0
        let top = size.height - topInset - (segments.isEmpty ? 76 : 112)
        let height = top - bottomInset - 24

        scroll = ScrollContainer(size: CGSize(width: contentWidth, height: height))
        scroll.position = CGPoint(x: size.width / 2, y: bottomInset + 24 + height / 2)
        addChild(scroll)

        statusLabel = SKLabelNode(fontNamed: Fonts.body)
        statusLabel.fontSize = 14
        statusLabel.fontColor = Palette.secondaryText
        statusLabel.horizontalAlignmentMode = .center
        statusLabel.numberOfLines = 3
        statusLabel.preferredMaxLayoutWidth = contentWidth - 20
        statusLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        statusLabel.isHidden = true
        addChild(statusLabel)
    }

    func selectSegment(_ index: Int) {
        guard index != selectedSegment else { return }
        selectedSegment = index
        for (position, button) in segmentedButtons.enumerated() {
            button.setHighlighted(position == index)
        }
        buildContent()
    }

    /// Populate the list. Called on appear and whenever a segment changes.
    func buildContent() {}

    func setRows(_ rows: [SKNode]) {
        statusLabel.isHidden = !rows.isEmpty
        scroll.setRows(rows, rowHeight: rowHeight)
    }

    func showStatus(_ message: String) {
        scroll.setRows([], rowHeight: rowHeight)
        statusLabel.text = message
        statusLabel.isHidden = false
    }

    func goBack() {
        let menu = MenuScene(size: size)
        menu.scaleMode = .resizeFill
        view?.presentScene(menu, transition: .push(with: .right, duration: 0.3))
    }

    // MARK: - Row helpers

    /// A generic list row: leading badge, title, subtitle and trailing value.
    func makeRow(
        badge: String,
        title: String,
        subtitle: String?,
        value: String,
        valueColor: SKColor = Palette.primaryText,
        highlighted: Bool = false,
        badgeNode: SKNode? = nil
    ) -> SKNode {
        let row = AccessibleNode()
        let rowSize = CGSize(width: contentWidth - 8, height: rowHeight - 6)

        let background = SKShapeNode(rectOf: rowSize, cornerRadius: 9)
        background.fillColor = highlighted
            ? Palette.accent.withAlphaComponent(0.18)
            : SKColor(white: 1, alpha: 0.05)
        background.strokeColor = highlighted ? Palette.accent : .clear
        background.lineWidth = highlighted ? 1.5 : 0
        row.addChild(background)

        let left = -(contentWidth - 8) / 2 + 14

        if let badgeNode {
            badgeNode.position = CGPoint(x: left + 10, y: 0)
            row.addChild(badgeNode)
        } else {
            let badgeLabel = SKLabelNode(fontNamed: Fonts.body)
            badgeLabel.text = badge
            badgeLabel.fontSize = 15
            badgeLabel.fontColor = Palette.secondaryText
            badgeLabel.horizontalAlignmentMode = .left
            badgeLabel.verticalAlignmentMode = .center
            badgeLabel.position = CGPoint(x: left, y: 0)
            row.addChild(badgeLabel)
        }

        let valueLabel = SKLabelNode(fontNamed: Fonts.display)
        valueLabel.text = value
        valueLabel.fontSize = 16
        valueLabel.fontColor = valueColor
        valueLabel.horizontalAlignmentMode = .right
        valueLabel.verticalAlignmentMode = .center
        valueLabel.position = CGPoint(x: (contentWidth - 8) / 2 - 14, y: 0)
        row.addChild(valueLabel)

        // Text must stop before the value column, otherwise it runs underneath it.
        let textStart = left + 42
        let textBudget = valueLabel.frame.minX - 10 - textStart

        let titleLabel = SKLabelNode(fontNamed: Fonts.display)
        titleLabel.text = TextFit.truncate(title, toWidth: textBudget, fontNamed: Fonts.display, fontSize: 15)
        titleLabel.fontSize = 15
        titleLabel.fontColor = Palette.primaryText
        titleLabel.horizontalAlignmentMode = .left
        titleLabel.verticalAlignmentMode = .center
        titleLabel.position = CGPoint(x: textStart, y: subtitle == nil ? 0 : 7)
        row.addChild(titleLabel)

        if let subtitle {
            let subtitleLabel = SKLabelNode(fontNamed: Fonts.body)
            subtitleLabel.text = TextFit.truncate(
                subtitle,
                toWidth: textBudget,
                fontNamed: Fonts.body,
                fontSize: 11
            )
            subtitleLabel.fontSize = 11
            subtitleLabel.fontColor = Palette.secondaryText
            subtitleLabel.horizontalAlignmentMode = .left
            subtitleLabel.verticalAlignmentMode = .center
            subtitleLabel.position = CGPoint(x: textStart, y: -8)
            row.addChild(subtitleLabel)
        }

        // One element per row rather than four: VoiceOver reads "Best score,
        // 58" instead of making the cursor walk badge, title, subtitle, value.
        // The untruncated strings are used, so nothing is lost to the ellipsis
        // the visible labels may carry.
        row.describe(
            accessibilitySentence(badge, title, subtitle, value),
            size: rowSize,
            traits: highlighted ? [.staticText, .selected] : .staticText
        )

        return row
    }

    /// Describe the text of a row that carries its own button.
    ///
    /// Such a row cannot be an accessibility element itself — an element hides
    /// its children, which would take the button out of the tree — so the text
    /// is published as a sibling covering everything to the left of `button`.
    func describeRowText(_ label: String, in row: SKNode, leftOf button: ButtonNode) {
        let leftEdge = -(contentWidth - 8) / 2
        let width = max(0, button.position.x - button.size.width / 2 - 8 - leftEdge)
        guard width > 0 else { return }

        let text = AccessibleNode()
        text.position = CGPoint(x: leftEdge + width / 2, y: 0)
        text.describe(label, size: CGSize(width: width, height: rowHeight - 6))
        row.addChild(text)
    }
}
