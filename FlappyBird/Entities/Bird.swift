import SpriteKit

/// The player-controlled bird.
///
/// Owns its own animation, trail, shield aura and rotation so the scene only has
/// to say `bird.flap()` / `bird.updateRotation()`.
final class Bird: SKSpriteNode {

    private static let frameNames = ["bird-01", "bird-02", "bird-03", "bird-04"]

    private var trail: SKEmitterNode?
    private var shieldAura: SKShapeNode?
    private var baseSize: CGSize = .zero

    /// `true` while the shrink power-up is active.
    private(set) var isShrunk = false

    // MARK: - Construction

    /// Build a bird with the given skin.
    static func make(skin: BirdSkin) -> Bird {
        let textures = frameNames.map { name -> SKTexture in
            let texture = SKTexture(imageNamed: name)
            texture.filteringMode = .nearest
            return texture
        }

        let bird = Bird(texture: textures.first)
        bird.setScale(GameConfig.birdScale)
        bird.zPosition = ZPosition.bird
        bird.baseSize = bird.size
        bird.apply(skin: skin)
        bird.startFlapping(textures: textures)
        return bird
    }

    /// Recolour the sprite for a skin.
    func apply(skin: BirdSkin) {
        color = skin.tint
        colorBlendFactor = skin.blend
        trail?.particleColor = skin.trailColor
    }

    private func startFlapping(textures: [SKTexture]) {
        // Wing beat uses the first two frames; the remaining frames exist for
        // the death tumble and menu preview.
        let wings = Array(textures.prefix(2))
        guard wings.count == 2 else { return }
        run(.repeatForever(.animate(with: wings, timePerFrame: 0.18)), withKey: "flap-animation")
    }

    // MARK: - Physics

    /// Attach a circular body. Kept out of `make` so the scene controls timing.
    func attachPhysics() {
        // A slightly smaller radius than the sprite makes near-misses feel fair;
        // the mass is pinned so that does not change the flight model.
        let body = SKPhysicsBody(circleOfRadius: size.height / 2.4)
        body.mass = GameConfig.birdMass
        body.isDynamic = true
        body.allowsRotation = false
        body.restitution = 0
        body.linearDamping = 0
        body.categoryBitMask = PhysicsCategory.bird.rawValue
        // The ceiling has to be here, not only in `contactTestBitMask`.
        // SpriteKit collisions are not symmetric: a body is stopped only by the
        // categories in *its own* collision mask, so listing the bird on the
        // ceiling was not enough — the bird flew straight through it, climbed
        // over the top pipe and skipped the gap entirely.
        body.collisionBitMask = PhysicsCategory.world
            .union(.pipe)
            .union(.ceiling)
            .rawValue
        body.contactTestBitMask = PhysicsCategory.world
            .union(.pipe)
            .union(.scoreGate)
            .union(.coin)
            .union(.powerUp)
            .union(.ceiling)
            .rawValue
        physicsBody = body
    }

    /// Stop colliding with pipes so the corpse falls to the ground cleanly.
    func enterDeathState() {
        physicsBody?.collisionBitMask = PhysicsCategory.world.rawValue
        physicsBody?.contactTestBitMask = PhysicsCategory.world.rawValue
        removeAction(forKey: "flap-animation")
        trail?.particleBirthRate = 0
        run(.rotate(byAngle: -.pi * 2, duration: 0.9))
    }

    func flap(impulse: CGFloat = GameConfig.flapImpulse) {
        physicsBody?.velocity = CGVector(dx: 0, dy: 0)
        physicsBody?.applyImpulse(CGVector(dx: 0, dy: impulse))
    }

    /// Clamp vertical speed so the bird stays controllable at any frame rate.
    func clampVelocity() {
        guard let body = physicsBody else { return }
        let dy = min(GameConfig.maxRiseSpeed, max(GameConfig.maxFallSpeed, body.velocity.dy))
        body.velocity = CGVector(dx: body.velocity.dx, dy: dy)
    }

    /// Keep the bird near its lane.
    ///
    /// Wind applies horizontal impulses every frame and nothing else damps them,
    /// so without this the bird slowly sails off the side of the screen. Drift is
    /// capped and gently springs back to the anchor once the gust passes.
    func clampHorizontal(anchorX: CGFloat, maxDrift: CGFloat, deltaTime: TimeInterval) {
        guard let body = physicsBody else { return }

        // Bound the lateral speed so a long gust cannot build up momentum.
        let dx = min(150, max(-150, body.velocity.dx))
        body.velocity = CGVector(dx: dx, dy: body.velocity.dy)

        let offset = position.x - anchorX
        if abs(offset) > maxDrift {
            position.x = anchorX + (offset < 0 ? -maxDrift : maxDrift)
            body.velocity = CGVector(dx: 0, dy: body.velocity.dy)
        } else if abs(offset) > 0.5 {
            // Ease back toward the lane — about 2 points per frame at 60fps.
            position.x -= offset * min(1, CGFloat(deltaTime) * 2.2)
        }
    }

    /// Tilt with vertical velocity: nose up while rising, dive while falling.
    func updateRotation() {
        guard let body = physicsBody else { return }
        let factor: CGFloat = body.velocity.dy < 0 ? 0.0028 : 0.0011
        zRotation = min(max(-1.05, body.velocity.dy * factor), 0.48)
    }

    // MARK: - Effects

    func addTrail(color: SKColor) {
        guard trail == nil else { return }
        let emitter = SKEmitterNode()
        emitter.particleTexture = ParticleTextures.dot
        emitter.particleBirthRate = 26
        emitter.particleLifetime = 0.55
        emitter.particleAlpha = 0.5
        emitter.particleAlphaSpeed = -0.9
        emitter.particleScale = 0.28
        emitter.particleScaleSpeed = -0.35
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        emitter.position = CGPoint(x: -size.width / 3, y: 0)
        emitter.zPosition = -1
        emitter.targetNode = parent
        addChild(emitter)
        trail = emitter
    }

    func setTrailActive(_ active: Bool) {
        trail?.particleBirthRate = active ? 26 : 0
    }

    func setShieldVisible(_ visible: Bool) {
        if visible {
            guard shieldAura == nil else { return }
            let radius = size.width * 0.85
            let aura = SKShapeNode(circleOfRadius: radius)
            aura.strokeColor = PowerUpKind.shield.color
            aura.lineWidth = 2.5
            aura.glowWidth = 3
            aura.fillColor = PowerUpKind.shield.color.withAlphaComponent(0.12)
            aura.zPosition = -2
            aura.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.45, duration: 0.6),
                .fadeAlpha(to: 1.0, duration: 0.6),
            ])))
            addChild(aura)
            shieldAura = aura
        } else {
            shieldAura?.removeFromParent()
            shieldAura = nil
        }
    }

    /// Apply or remove the shrink power-up, preserving the physics body scale.
    func setShrunk(_ shrunk: Bool) {
        guard shrunk != isShrunk else { return }
        isShrunk = shrunk
        let target = shrunk ? GameConfig.birdScale * GameConfig.shrinkFactor : GameConfig.birdScale
        run(.scale(to: target, duration: 0.2)) { [weak self] in
            guard let self, self.physicsBody != nil else { return }
            // Rebuild the body so the hitbox matches the new sprite size.
            let wasVelocity = self.physicsBody?.velocity ?? .zero
            self.attachPhysics()
            self.physicsBody?.velocity = wasVelocity
        }
    }

    /// Emit a burst of feathers — used on death and on shield absorption.
    func burstFeathers(color: SKColor) {
        let emitter = SKEmitterNode()
        emitter.particleTexture = ParticleTextures.pixel
        emitter.numParticlesToEmit = 26
        emitter.particleBirthRate = 400
        emitter.particleLifetime = 0.8
        emitter.particleSpeed = 180
        emitter.particleSpeedRange = 120
        emitter.emissionAngleRange = .pi * 2
        emitter.particleAlpha = 0.9
        emitter.particleAlphaSpeed = -1.2
        emitter.particleScale = 0.9
        emitter.particleScaleRange = 0.4
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1
        emitter.yAcceleration = -320
        emitter.zPosition = ZPosition.particles
        emitter.position = position
        emitter.targetNode = parent
        parent?.addChild(emitter)
        emitter.run(.sequence([.wait(forDuration: 1.4), .removeFromParent()]))
    }

    /// Reset to the starting position and state for a new run.
    func prepareForNewRun(at position: CGPoint) {
        removeAllActions()
        self.position = position
        zRotation = 0
        setScale(GameConfig.birdScale)
        isShrunk = false
        speed = 1
        alpha = 1
        setShieldVisible(false)
        setTrailActive(true)
        attachPhysics()
        physicsBody?.velocity = .zero
        physicsBody?.isDynamic = true
        startFlapping(textures: Bird.frameNames.map {
            let texture = SKTexture(imageNamed: $0)
            texture.filteringMode = .nearest
            return texture
        })
    }

    /// Idle bob used on the "get ready" screen.
    func startIdleBob() {
        removeAction(forKey: "idle-bob")
        let bob = SKAction.sequence([
            .moveBy(x: 0, y: 12, duration: 0.42),
            .moveBy(x: 0, y: -12, duration: 0.42),
        ])
        bob.timingMode = .easeInEaseOut
        run(.repeatForever(bob), withKey: "idle-bob")
    }

    func stopIdleBob() {
        removeAction(forKey: "idle-bob")
    }
}
