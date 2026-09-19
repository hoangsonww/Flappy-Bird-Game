import SpriteKit

/// Scrolling background and ground.
///
/// Three layers move at different rates to fake depth: distant clouds, the sky
/// strip, and the ground. All of them live inside one container so the scene can
/// freeze the world by setting `container.speed = 0`.
final class ParallaxWorld {

    private let container: SKNode
    private let sceneSize: CGSize

    private var groundSprites: [SKSpriteNode] = []
    private var skySprites: [SKSpriteNode] = []
    private var cloudSprites: [SKSpriteNode] = []

    /// Height of the collidable ground, in points.
    private(set) var groundHeight: CGFloat = 0

    init(container: SKNode, sceneSize: CGSize) {
        self.container = container
        self.sceneSize = sceneSize
    }

    /// Build every layer. Call once, from `didMove(to:)`.
    func build(tint: SKColor, tintStrength: CGFloat, reduceMotion: Bool) {
        let groundTexture = SKTexture(imageNamed: "land")
        groundTexture.filteringMode = .nearest
        groundHeight = groundTexture.size().height * GameConfig.groundScale

        buildSky(tint: tint, tintStrength: tintStrength, reduceMotion: reduceMotion)
        buildClouds(reduceMotion: reduceMotion)
        buildGround(texture: groundTexture, tint: tint, tintStrength: tintStrength, reduceMotion: reduceMotion)
    }

    private func buildGround(
        texture: SKTexture,
        tint: SKColor,
        tintStrength: CGFloat,
        reduceMotion: Bool
    ) {
        let width = texture.size().width * GameConfig.groundScale
        let tileCount = 2 + Int(sceneSize.width / width)
        let duration = TimeInterval(0.02 * width)

        for index in 0...tileCount {
            let sprite = SKSpriteNode(texture: texture)
            sprite.setScale(GameConfig.groundScale)
            sprite.color = tint
            sprite.colorBlendFactor = tintStrength
            sprite.zPosition = ZPosition.ground
            sprite.position = CGPoint(x: CGFloat(index) * width, y: sprite.size.height / 2)
            if !reduceMotion {
                sprite.run(ParallaxWorld.scrollForever(distance: width, duration: duration))
            }
            container.addChild(sprite)
            groundSprites.append(sprite)
        }
    }

    private func buildSky(tint: SKColor, tintStrength: CGFloat, reduceMotion: Bool) {
        let texture = SKTexture(imageNamed: "sky")
        texture.filteringMode = .nearest
        let width = texture.size().width * GameConfig.groundScale
        let groundTexture = SKTexture(imageNamed: "land")
        let baseY = texture.size().height * GameConfig.groundScale / 2
            + groundTexture.size().height * GameConfig.groundScale
        let tileCount = 2 + Int(sceneSize.width / width)
        let duration = TimeInterval(0.1 * width)

        for index in 0...tileCount {
            let sprite = SKSpriteNode(texture: texture)
            sprite.setScale(GameConfig.groundScale)
            sprite.color = tint
            sprite.colorBlendFactor = tintStrength
            sprite.zPosition = ZPosition.distantCity
            sprite.position = CGPoint(x: CGFloat(index) * width, y: baseY)
            if !reduceMotion {
                sprite.run(ParallaxWorld.scrollForever(distance: width, duration: duration))
            }
            container.addChild(sprite)
            skySprites.append(sprite)
        }
    }

    /// Soft procedural clouds — no art needed, and they read well at any size.
    private func buildClouds(reduceMotion: Bool) {
        guard !reduceMotion else { return }

        for index in 0..<5 {
            let cloud = ParallaxWorld.makeCloud()
            cloud.zPosition = ZPosition.clouds
            cloud.alpha = 0.32
            cloud.position = CGPoint(
                x: CGFloat(index) * sceneSize.width / 3.0,
                y: sceneSize.height * CGFloat.random(in: 0.58...0.88)
            )
            let distance = sceneSize.width + cloud.size.width
            cloud.run(ParallaxWorld.scrollForever(distance: distance, duration: TimeInterval(0.06 * distance)))
            container.addChild(cloud)
            cloudSprites.append(cloud)
        }
    }

    private static func makeCloud() -> SKSpriteNode {
        let size = CGSize(width: CGFloat.random(in: 90...170), height: CGFloat.random(in: 34...56))
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            UIColor.white.setFill()
            // Three overlapping ellipses make a believable pixel-ish cloud.
            UIBezierPath(ovalIn: CGRect(x: 0, y: size.height * 0.3, width: size.width * 0.6, height: size.height * 0.7)).fill()
            UIBezierPath(ovalIn: CGRect(x: size.width * 0.25, y: 0, width: size.width * 0.55, height: size.height)).fill()
            UIBezierPath(ovalIn: CGRect(x: size.width * 0.45, y: size.height * 0.25, width: size.width * 0.55, height: size.height * 0.75)).fill()
        }
        let texture = SKTexture(image: image)
        return SKSpriteNode(texture: texture)
    }

    /// Move left by `distance`, snap back, repeat.
    private static func scrollForever(distance: CGFloat, duration: TimeInterval) -> SKAction {
        let move = SKAction.moveBy(x: -distance, y: 0, duration: duration)
        let reset = SKAction.moveBy(x: distance, y: 0, duration: 0)
        return .repeatForever(.sequence([move, reset]))
    }

    /// Re-tint every layer when the time of day changes.
    func applyTint(_ tint: SKColor, strength: CGFloat, animated: Bool) {
        let sprites = groundSprites + skySprites
        for sprite in sprites {
            if animated {
                sprite.run(.colorize(with: tint, colorBlendFactor: strength, duration: 1.1))
            } else {
                sprite.color = tint
                sprite.colorBlendFactor = strength
            }
        }
        for cloud in cloudSprites {
            cloud.run(.fadeAlpha(to: strength > 0.4 ? 0.16 : 0.32, duration: animated ? 1.1 : 0))
        }
    }

    /// The collidable floor. Built separately from the visual ground tiles so the
    /// body can be a single rectangle.
    static func makeGroundBody(sceneWidth: CGFloat, groundHeight: CGFloat) -> SKNode {
        let node = SKNode()
        node.position = CGPoint(x: sceneWidth / 2, y: groundHeight / 2)
        let body = SKPhysicsBody(rectangleOf: CGSize(width: sceneWidth * 2, height: groundHeight))
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.world.rawValue
        body.contactTestBitMask = PhysicsCategory.bird.rawValue
        node.physicsBody = body
        return node
    }

    /// An invisible ceiling. Without it a player can climb above every pipe.
    static func makeCeilingBody(sceneSize: CGSize) -> SKNode {
        let node = SKNode()
        node.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height + 40)
        let body = SKPhysicsBody(rectangleOf: CGSize(width: sceneSize.width * 2, height: 20))
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.ceiling.rawValue
        body.contactTestBitMask = PhysicsCategory.bird.rawValue
        body.collisionBitMask = PhysicsCategory.bird.rawValue
        node.physicsBody = body
        return node
    }
}
