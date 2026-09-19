import SpriteKit

/// Bird skins, bought with coins earned in game.
final class ShopScene: ListScene {

    override var screenTitle: String { "SHOP" }
    override var rowHeight: CGFloat { 56 }

    private let store = GameStore.shared
    private let settings = Settings.shared

    override func buildContent() {
        var rows: [SKNode] = [
            makeRow(
                badge: "",
                title: "Wallet",
                subtitle: "Earned in runs · combos multiply",
                value: String(store.profile.wallet),
                valueColor: SKColor(red: 0.99, green: 0.82, blue: 0.28, alpha: 1),
                highlighted: true,
                badgeNode: CoinIcon.node(radius: 9)
            ),
        ]

        rows += BirdSkin.allCases.map { skin in makeSkinRow(skin) }
        setRows(rows)
    }

    private func makeSkinRow(_ skin: BirdSkin) -> SKNode {
        let unlocked = store.isUnlocked(skin)
        let equipped = settings.selectedSkin == skin

        let row = SKNode()

        let background = SKShapeNode(
            rectOf: CGSize(width: contentWidth - 8, height: rowHeight - 6),
            cornerRadius: 9
        )
        background.fillColor = equipped ? Palette.positive.withAlphaComponent(0.16) : SKColor(white: 1, alpha: 0.05)
        background.strokeColor = equipped ? Palette.positive : .clear
        background.lineWidth = equipped ? 1.5 : 0
        row.addChild(background)

        let left = -(contentWidth - 8) / 2 + 16

        // Live sprite preview so the tint is obvious before buying.
        let texture = SKTexture(imageNamed: "bird-01")
        texture.filteringMode = .nearest
        let preview = SKSpriteNode(texture: texture)
        preview.setScale(1.5)
        preview.color = skin.tint
        preview.colorBlendFactor = skin.blend
        preview.alpha = unlocked ? 1 : 0.35
        preview.position = CGPoint(x: left + 12, y: 0)
        row.addChild(preview)

        let name = SKLabelNode(fontNamed: Fonts.display)
        name.text = skin.displayName
        name.fontSize = 16
        name.fontColor = Palette.primaryText
        name.horizontalAlignmentMode = .left
        name.verticalAlignmentMode = .center
        name.position = CGPoint(x: left + 40, y: 8)
        row.addChild(name)

        let detail = SKLabelNode(fontNamed: Fonts.body)
        detail.text = unlocked
            ? (equipped ? "Equipped" : "Owned — tap to equip")
            : "Costs \(skin.price) coins"
        detail.fontSize = 11
        detail.fontColor = unlocked ? Palette.secondaryText : SKColor(red: 0.99, green: 0.82, blue: 0.28, alpha: 1)
        detail.horizontalAlignmentMode = .left
        detail.verticalAlignmentMode = .center
        detail.position = CGPoint(x: left + 40, y: -9)
        row.addChild(detail)

        let actionTitle = unlocked ? (equipped ? "✓" : "EQUIP") : "BUY"
        let canAfford = unlocked || store.profile.wallet >= skin.price
        let button = ButtonNode(
            title: actionTitle,
            size: CGSize(width: 74, height: 34),
            fontSize: 13,
            fillColor: canAfford ? Palette.buttonFill : SKColor(white: 0.2, alpha: 0.6)
        ) { [weak self] in
            self?.handleTap(on: skin)
        }
        button.position = CGPoint(x: (contentWidth - 8) / 2 - 52, y: 0)
        button.setEnabled(!equipped && canAfford)
        row.addChild(button)

        return row
    }

    private func handleTap(on skin: BirdSkin) {
        if store.isUnlocked(skin) {
            settings.selectedSkin = skin
            AudioManager.shared.play(.powerUp)
        } else if store.purchase(skin) {
            settings.selectedSkin = skin
            AudioManager.shared.play(.achievement)
            Haptics.shared.achievement()
        } else {
            AudioManager.shared.play(.crash)
            showStatus("Not enough coins for \(skin.displayName).\nYou need \(skin.price - store.profile.wallet) more.")
            return
        }
        buildContent()
    }
}
