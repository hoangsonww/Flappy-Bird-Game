import SpriteKit

/// Coins and power-up pickups.
///
/// Both are drawn in code so the game needs no extra art, and both carry the
/// metadata the scene needs in `userData` — avoiding a cast-heavy hierarchy.
enum Collectible {

    static let coinKey = "coin"
    static let powerUpKey = "powerUp"

    /// A spinning coin worth `GameConfig.coinValue` times the current combo.
    static func makeCoin() -> SKNode {
        let node = SKShapeNode(circleOfRadius: 11)
        node.fillColor = SKColor(red: 0.99, green: 0.82, blue: 0.28, alpha: 1)
        node.strokeColor = SKColor(red: 0.75, green: 0.55, blue: 0.10, alpha: 1)
        node.lineWidth = 2
        node.glowWidth = 1.5
        node.zPosition = ZPosition.collectible
        node.name = coinKey

        let inner = SKShapeNode(circleOfRadius: 5)
        inner.fillColor = SKColor(red: 1.0, green: 0.93, blue: 0.62, alpha: 1)
        inner.strokeColor = .clear
        node.addChild(inner)

        let body = SKPhysicsBody(circleOfRadius: 13)
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.coin.rawValue
        body.contactTestBitMask = PhysicsCategory.bird.rawValue
        body.collisionBitMask = 0
        node.physicsBody = body

        // Fake a 3D spin by squashing horizontally.
        let spin = SKAction.sequence([
            .scaleX(to: 0.25, duration: 0.45),
            .scaleX(to: 1.0, duration: 0.45),
        ])
        spin.timingMode = .easeInEaseOut
        node.run(.repeatForever(spin))

        return node
    }

    /// A pulsing power-up badge.
    static func makePowerUp(kind: PowerUpKind) -> SKNode {
        let node = SKShapeNode(circleOfRadius: 16)
        node.fillColor = kind.color.withAlphaComponent(0.22)
        node.strokeColor = kind.color
        node.lineWidth = 2.5
        node.glowWidth = 2
        node.zPosition = ZPosition.collectible
        node.name = powerUpKey
        node.userData = ["kind": kind.rawValue]

        let label = SKLabelNode(text: kind.symbol)
        label.fontSize = 17
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        node.addChild(label)

        let body = SKPhysicsBody(circleOfRadius: 18)
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.powerUp.rawValue
        body.contactTestBitMask = PhysicsCategory.bird.rawValue
        body.collisionBitMask = 0
        node.physicsBody = body

        let pulse = SKAction.sequence([
            .scale(to: 1.15, duration: 0.5),
            .scale(to: 0.95, duration: 0.5),
        ])
        pulse.timingMode = .easeInEaseOut
        node.run(.repeatForever(pulse))
        node.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 6)))

        return node
    }

    /// Read the power-up kind out of a collected node.
    static func kind(from node: SKNode) -> PowerUpKind? {
        guard let raw = node.userData?["kind"] as? String else { return nil }
        return PowerUpKind(rawValue: raw)
    }

    /// Play the pickup animation and remove the node.
    static func collect(_ node: SKNode, tint: SKColor) {
        node.physicsBody = nil
        node.removeAllActions()
        node.run(.sequence([
            .group([
                .scale(to: 1.9, duration: 0.18),
                .fadeOut(withDuration: 0.18),
                .moveBy(x: 0, y: 26, duration: 0.18),
            ]),
            .removeFromParent(),
        ]))

        let sparkle = SKEmitterNode()
        sparkle.particleTexture = ParticleTextures.dot
        sparkle.numParticlesToEmit = 14
        sparkle.particleBirthRate = 300
        sparkle.particleLifetime = 0.5
        sparkle.particleSpeed = 110
        sparkle.particleSpeedRange = 60
        sparkle.emissionAngleRange = .pi * 2
        sparkle.particleAlpha = 0.9
        sparkle.particleAlphaSpeed = -1.8
        sparkle.particleScale = 0.4
        sparkle.particleScaleSpeed = -0.5
        sparkle.particleColor = tint
        sparkle.particleColorBlendFactor = 1
        sparkle.particleBlendMode = .add
        sparkle.position = node.position
        sparkle.zPosition = ZPosition.particles
        node.parent?.addChild(sparkle)
        sparkle.run(.sequence([.wait(forDuration: 0.8), .removeFromParent()]))
    }
}
