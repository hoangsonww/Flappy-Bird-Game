import CoreGraphics
import Foundation
import SpriteKit

/// Ambient weather that changes how a run feels without changing the rules much.
enum Weather: String, CaseIterable {
    case clear
    case windy
    case rain
    case fog

    var displayName: String {
        switch self {
        case .clear: return "Clear"
        case .windy: return "Windy"
        case .rain: return "Rain"
        case .fog: return "Fog"
        }
    }

    var symbol: String {
        switch self {
        case .clear: return "☀️"
        case .windy: return "🌬"
        case .rain: return "🌧"
        case .fog: return "🌫"
        }
    }

    /// Horizontal force applied to the bird, in impulse units per second.
    var windForce: CGFloat {
        switch self {
        case .windy: return 26
        default: return 0
        }
    }

    /// Extra downward pull, layered on top of gravity.
    var downdraft: CGFloat {
        switch self {
        case .rain: return 0.6
        default: return 0
        }
    }

    /// Opacity of the fog overlay.
    var fogAlpha: CGFloat {
        switch self {
        case .fog: return 0.28
        default: return 0
        }
    }

    static func random(using generator: inout SeededRandom) -> Weather {
        // Clear weather is weighted heavily so the game stays recognisable.
        let roll = generator.nextUnit()
        switch roll {
        case ..<0.62: return .clear
        case ..<0.78: return .windy
        case ..<0.91: return .rain
        default: return .fog
        }
    }
}

/// Builds and drives the weather visuals for a scene.
///
/// Emitters are created programmatically — the project ships no `.sks` particle
/// files, so everything is configured in code and can be tuned in one place.
final class WeatherSystem {
    private(set) var weather: Weather = .clear
    private weak var container: SKNode?
    private var rainEmitter: SKEmitterNode?
    private var fogOverlay: SKSpriteNode?
    private var windGustDirection: CGFloat = 1
    private var nextGustFlip: TimeInterval = 0

    /// Seconds the bird has spent inside wind — feeds the Storm Chaser achievement.
    private(set) var secondsInWind: TimeInterval = 0

    init(container: SKNode) {
        self.container = container
    }

    func apply(_ weather: Weather, sceneSize: CGSize, reduceMotion: Bool) {
        self.weather = weather
        teardown()

        guard !reduceMotion else { return }

        if weather == .rain {
            let emitter = WeatherSystem.makeRainEmitter(sceneSize: sceneSize)
            emitter.zPosition = ZPosition.weather
            container?.addChild(emitter)
            rainEmitter = emitter
        }

        if weather == .fog {
            let overlay = SKSpriteNode(color: SKColor(white: 0.85, alpha: 1), size: sceneSize)
            overlay.alpha = 0
            overlay.zPosition = ZPosition.weather
            overlay.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
            overlay.run(.fadeAlpha(to: weather.fogAlpha, duration: 1.2))
            container?.addChild(overlay)
            fogOverlay = overlay
        }
    }

    /// Per-frame physics contribution. Returns the horizontal force to apply.
    func update(deltaTime: TimeInterval, elapsed: TimeInterval) -> CGVector {
        guard weather == .windy else { return .zero }

        secondsInWind += deltaTime

        // Gusts reverse every few seconds so the player has to keep adjusting.
        if elapsed > nextGustFlip {
            windGustDirection *= -1
            nextGustFlip = elapsed + Double.random(in: 2.4...4.8)
        }

        return CGVector(dx: weather.windForce * windGustDirection * CGFloat(deltaTime), dy: 0)
    }

    func teardown() {
        rainEmitter?.removeFromParent()
        rainEmitter = nil
        fogOverlay?.removeFromParent()
        fogOverlay = nil
    }

    func reset() {
        secondsInWind = 0
        nextGustFlip = 0
        windGustDirection = 1
    }

    // MARK: - Emitter construction

    private static func makeRainEmitter(sceneSize: CGSize) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = ParticleTextures.streak
        emitter.particleBirthRate = 180
        emitter.particleLifetime = 1.4
        emitter.particlePositionRange = CGVector(dx: sceneSize.width * 1.4, dy: 0)
        emitter.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height + 20)
        emitter.emissionAngle = -.pi / 2.2
        emitter.emissionAngleRange = 0.08
        emitter.particleSpeed = 820
        emitter.particleSpeedRange = 140
        emitter.particleAlpha = 0.38
        emitter.particleAlphaRange = 0.15
        emitter.particleScale = 0.55
        emitter.particleScaleRange = 0.2
        emitter.particleColor = SKColor(red: 0.75, green: 0.86, blue: 1.0, alpha: 1)
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        return emitter
    }
}

/// Small procedurally drawn textures used by every emitter in the game.
///
/// Generating them once avoids shipping binary particle assets and keeps the
/// look consistent.
enum ParticleTextures {
    /// A soft round dot — sparks, feathers, coin shimmer.
    static let dot: SKTexture = {
        let size = CGSize(width: 12, height: 12)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cg = context.cgContext
            let colors = [
                UIColor.white.withAlphaComponent(1).cgColor,
                UIColor.white.withAlphaComponent(0).cgColor,
            ] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) {
                cg.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: 6, y: 6),
                    startRadius: 0,
                    endCenter: CGPoint(x: 6, y: 6),
                    endRadius: 6,
                    options: []
                )
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }()

    /// A vertical streak used for rain.
    static let streak: SKTexture = {
        let size = CGSize(width: 3, height: 14)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 1.5)
            path.fill()
            _ = context
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }()

    /// A small square — pixel-art dust and debris.
    static let pixel: SKTexture = {
        let size = CGSize(width: 4, height: 4)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        return texture
    }()
}
