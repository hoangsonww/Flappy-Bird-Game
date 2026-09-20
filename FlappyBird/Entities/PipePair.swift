import SpriteKit

/// One top/bottom pipe pair plus its scoring gate and optional pickup.
///
/// The node owns everything that scrolls together, so the scene can move and
/// remove a whole obstacle with a single action.
///
/// ## Why the sprites are nine-sliced
///
/// `PipeUp.png` / `PipeDown.png` are 30×160 with a 12px cap. Drawn at a fixed
/// size they leave open sky above the top pipe and a floating gap below the
/// bottom one on any modern phone. Each sprite is therefore stretched to reach
/// the screen edge using `centerRect`, which scales only the shaft and leaves
/// the cap pixel-perfect.
final class PipePair: SKNode {

    /// What (if anything) sits inside the gap.
    enum GapContent {
        case none
        case coin
        case powerUp(PowerUpKind)
    }

    /// Cap height as a fraction of the texture — measured from the artwork.
    private static let capFraction: CGFloat = 12.0 / 160.0

    /// How far past the screen edge a pipe extends, so nothing pops in.
    private static let overshoot: CGFloat = 200

    private(set) var hasScored = false

    /// Scene-space centre of the opening, and its height. Stored rather than
    /// derived so anything aiming at the gap (the auto-pilot, future AI) reads
    /// the same number the pipes were built from.
    private(set) var gapCentre: CGFloat = 0
    private(set) var gapHeight: CGFloat = 0

    /// Mark the pair as counted so a second contact cannot double-score.
    func markScored() {
        hasScored = true
    }

    /// Strip every physics body, for a replay.
    ///
    /// Playback positions the pair directly from the recording; leaving the
    /// bodies attached would let it collide with a replayed bird that is not
    /// simulated, and score against a gate nobody is passing.
    func removePhysics() {
        physicsBody = nil
        for node in children {
            node.physicsBody = nil
        }
    }

    /// Everything needed to build one obstacle.
    struct Spec {
        /// y position of the middle of the gap, in scene coordinates.
        var gapCentre: CGFloat
        /// Vertical opening between the pipes.
        var gapHeight: CGFloat
        /// Used to size the pipes and the full-height scoring gate.
        var sceneHeight: CGFloat
        /// What to place inside the gap.
        var content: GapContent
        /// Time-of-day tint applied to the pipe sprites, and its blend factor.
        var tint: SKColor
        var tintStrength: CGFloat
        /// Whether the pair should oscillate vertically (harder modes).
        var moving: Bool
    }

    /// Build a pair from a `Spec`.
    static func make(_ spec: Spec) -> PipePair {
        let gapCentre = spec.gapCentre
        let gapHeight = spec.gapHeight
        let sceneHeight = spec.sceneHeight
        let content = spec.content
        let tint = spec.tint
        let tintStrength = spec.tintStrength
        let moving = spec.moving

        let pair = PipePair()
        // No zPosition here. SpriteKit adds a node's z to its ancestors', and
        // the scene's `pipesNode` already carries `ZPosition.pipes` — setting it
        // again put the pair at -20, exactly tying the sky/city band. Tied z
        // draws in an undefined order, which is why a bottom pipe sometimes
        // vanished behind the background partway down instead of reaching the
        // ground, and sometimes did not.
        pair.gapCentre = gapCentre
        pair.gapHeight = gapHeight

        let upTexture = SKTexture(imageNamed: "PipeUp")
        upTexture.filteringMode = .nearest
        let downTexture = SKTexture(imageNamed: "PipeDown")
        downTexture.filteringMode = .nearest

        let width = upTexture.size().width * GameConfig.pipeScale
        let gapTop = gapCentre + gapHeight / 2
        let gapBottom = gapCentre - gapHeight / 2

        // ── Bottom pipe: cap at the gap, shaft stretched down past the ground ──
        let bottomHeight = max(width, gapBottom + overshoot)
        let bottom = SKSpriteNode(texture: upTexture)
        // The cap sits at the top of PipeUp, so only the lower part may stretch.
        bottom.centerRect = CGRect(x: 0, y: 0, width: 1, height: 1 - capFraction)
        bottom.size = CGSize(width: width, height: bottomHeight)
        bottom.color = tint
        bottom.colorBlendFactor = tintStrength
        bottom.position = CGPoint(x: 0, y: gapBottom - bottomHeight / 2)
        bottom.physicsBody = makeBody(size: bottom.size)
        pair.addChild(bottom)

        // ── Top pipe: cap at the gap, shaft stretched up past the ceiling ─────
        let topHeight = max(width, sceneHeight + overshoot - gapTop)
        let top = SKSpriteNode(texture: downTexture)
        // The cap sits at the bottom of PipeDown, so only the upper part stretches.
        top.centerRect = CGRect(x: 0, y: capFraction, width: 1, height: 1 - capFraction)
        top.size = CGSize(width: width, height: topHeight)
        top.color = tint
        top.colorBlendFactor = tintStrength
        top.position = CGPoint(x: 0, y: gapTop + topHeight / 2)
        top.physicsBody = makeBody(size: top.size)
        pair.addChild(top)

        // ── Scoring gate: a full-height sensor just past the pipes ────────────
        let gate = SKNode()
        gate.position = CGPoint(x: width / 2 + 2, y: sceneHeight / 2)
        let gateBody = SKPhysicsBody(rectangleOf: CGSize(width: 6, height: sceneHeight * 2))
        gateBody.isDynamic = false
        gateBody.categoryBitMask = PhysicsCategory.scoreGate.rawValue
        gateBody.contactTestBitMask = PhysicsCategory.bird.rawValue
        gateBody.collisionBitMask = 0
        gate.physicsBody = gateBody
        pair.addChild(gate)

        switch content {
        case .none:
            break
        case .coin:
            let coin = Collectible.makeCoin()
            coin.position = CGPoint(x: 0, y: gapCentre)
            pair.addChild(coin)
        case .powerUp(let kind):
            let node = Collectible.makePowerUp(kind: kind)
            node.position = CGPoint(x: 0, y: gapCentre)
            pair.addChild(node)
        }

        if moving {
            // A gentle vertical drift; the amplitude stays well inside the gap so
            // the pair is always passable.
            let amplitude = min(42, gapHeight * 0.2)
            let drift = SKAction.sequence([
                .moveBy(x: 0, y: amplitude, duration: 1.4),
                .moveBy(x: 0, y: -amplitude * 2, duration: 2.8),
                .moveBy(x: 0, y: amplitude, duration: 1.4),
            ])
            drift.timingMode = .easeInEaseOut
            pair.run(.repeatForever(drift), withKey: "drift")
        }

        return pair
    }

    private static func makeBody(size: CGSize) -> SKPhysicsBody {
        let body = SKPhysicsBody(rectangleOf: size)
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.pipe.rawValue
        body.contactTestBitMask = PhysicsCategory.bird.rawValue
        return body
    }
}
