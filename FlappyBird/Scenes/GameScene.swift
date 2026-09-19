import SpriteKit
import UIKit

/// The playable scene.
///
/// Structure:
/// ```
/// GameScene
/// ├── worldNode          (everything that scrolls; speed = 0 freezes the game)
/// │   ├── sky / clouds / ground tiles   … ParallaxWorld
/// │   └── pipesNode → PipePair*         … obstacles, gates, pickups
/// ├── groundBody, ceilingBody           … static physics only
/// ├── ghostNode                         … translucent replay of the best run
/// ├── hud                               … HUDNode
/// └── overlayNode                       … pause / game-over panels
/// ```
///
/// `worldNode.speed` is the single lever for pausing and for slow-motion, so
/// there is never a mix of half-frozen actions.
final class GameScene: SKScene, SKPhysicsContactDelegate {

    // MARK: - Configuration

    /// Mode to play. Set before presenting.
    var mode: GameMode = .classic
    /// Present when `mode == .daily`.
    var dailyChallenge: DailyChallengeHelper.Challenge?

    // MARK: - Nodes

    private let worldNode = SKNode()
    private let pipesNode = SKNode()
    private let overlayNode = SKNode()
    private var ghostNode: SKSpriteNode?
    private var bird: Bird!
    private var hud: HUDNode!
    private var parallax: ParallaxWorld!
    private var weatherSystem: WeatherSystem!
    private var toasts: ToastPresenter!
    private var flashOverlay: SKSpriteNode?

    // MARK: - State

    private var state: GameState = .ready
    private var stats = RunStats()
    private var difficulty = DifficultyCurve(mode: .classic)
    private var powerUps = ActivePowerUps()
    private var generator = SeededRandom(seed: 1)
    private var timeOfDay: TimeOfDay = .day
    private var deathCause: DeathCause = .none

    private var lastUpdate: TimeInterval = 0
    private var elapsed: TimeInterval = 0
    private var spawnAccumulator: TimeInterval = 0
    private var currentSnapshot = DifficultySnapshot(
        pipeGap: GameConfig.baseVerticalPipeGap,
        spawnInterval: GameConfig.baseSpawnInterval,
        scrollRate: GameConfig.baseScrollRate,
        gravity: GameConfig.gravity
    )

    private var demoPilot = DemoPilot()
    private var ghostRecorder = GhostRecorder()
    private var ghostPlayer: GhostPlayer?
    private var achievementSystem = AchievementSystem()
    private var statusToken: UUID?

    private let store = GameStore.shared
    private let settings = Settings.shared

    /// Cached because `UIAccessibility` calls are not free in `update`.
    private var reduceMotion = false

    /// Live numbers overlay, enabled with `-debug-hud`.
    private var debugLabel: SKLabelNode?

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        reduceMotion = UIAccessibility.isReduceMotionEnabled

        scaleMode = .resizeFill
        physicsWorld.contactDelegate = self

        configureRun()
        buildWorld()
        buildBird()
        buildGhost()
        buildHUD()

        addChild(overlayNode)
        overlayNode.zPosition = ZPosition.overlay

        if LaunchOptions.showsDebugOverlay { buildDebugOverlay() }

        toasts = ToastPresenter(container: self, sceneSize: size)
        AudioManager.shared.start()
        Haptics.shared.prepare()

        statusToken = OnlineService.shared.observeStatus { [weak self] status in
            self?.hud?.setOnline(status.isOnline)
        }

        enterReadyState()
    }

    override func willMove(from view: SKView) {
        if let statusToken {
            OnlineService.shared.removeObserver(statusToken)
        }
        weatherSystem?.teardown()
    }

    /// Seed the run and resolve the difficulty curve for the chosen mode.
    private func configureRun() {
        if mode == .daily {
            let challenge = dailyChallenge ?? DailyChallengeHelper.derive(for: DailyChallengeHelper.todayKey())
            dailyChallenge = challenge
            stats.seed = challenge.seed
            generator = SeededRandom(stringSeed: challenge.seed)
            difficulty = DifficultyCurve(
                mode: challenge.mode,
                pipeGapOverride: challenge.pipeGap,
                gravityScale: challenge.gravityScale,
                speedScale: challenge.speedScale
            )
        } else {
            stats.seed = SeededRandom.newSeedString()
            generator = SeededRandom(stringSeed: stats.seed)
            difficulty = DifficultyCurve(mode: mode)
        }

        currentSnapshot = difficulty.snapshot(pipesPassed: 0)
        timeOfDay = .day
        backgroundColor = timeOfDay.skyColor
        physicsWorld.gravity = CGVector(dx: 0, dy: currentSnapshot.gravity)
    }

    private func buildWorld() {
        addChild(worldNode)
        worldNode.addChild(pipesNode)
        pipesNode.zPosition = ZPosition.pipes

        parallax = ParallaxWorld(container: worldNode, sceneSize: size)
        parallax.build(
            tint: timeOfDay.worldTint,
            tintStrength: timeOfDay.worldTintStrength,
            reduceMotion: reduceMotion
        )

        addChild(ParallaxWorld.makeGroundBody(sceneWidth: size.width, groundHeight: parallax.groundHeight))
        addChild(ParallaxWorld.makeCeilingBody(sceneSize: size))

        weatherSystem = WeatherSystem(container: self)
        let weather: Weather = {
            if let modifier = dailyChallenge?.modifier, let forced = DailyChallengeHelper.weather(for: modifier) {
                return forced
            }
            return mode == .zen ? .clear : Weather.random(using: &generator)
        }()
        weatherSystem.apply(weather, sceneSize: size, reduceMotion: reduceMotion)
    }

    private func buildBird() {
        bird = Bird.make(skin: settings.selectedSkin)
        bird.position = startPosition
        bird.addTrail(color: settings.selectedSkin.trailColor)
        addChild(bird)
    }

    /// Translucent replay of the player's best run, when one is recorded.
    private func buildGhost() {
        guard settings.ghostEnabled, mode != .daily, let ghost = store.ghost else { return }
        ghostPlayer = GhostPlayer(samples: ghost.samples, score: ghost.score)

        let texture = SKTexture(imageNamed: "bird-01")
        texture.filteringMode = .nearest
        let node = SKSpriteNode(texture: texture)
        node.setScale(GameConfig.birdScale)
        node.alpha = 0.26
        node.color = .white
        node.colorBlendFactor = 0.6
        node.zPosition = ZPosition.ghost
        node.position = CGPoint(x: startPosition.x - 26, y: startPosition.y)
        addChild(node)
        ghostNode = node
    }

    private func buildHUD() {
        let inset = view?.safeAreaInsets.top ?? 0
        hud = HUDNode(
            sceneSize: size,
            safeTop: inset,
            mode: mode,
            best: store.profile.bestScore(for: mode),
            onPause: { [weak self] in self?.pause() }
        )
        hud.setOnline(OnlineService.shared.status.isOnline)
        addChild(hud)
    }

    /// Developer overlay: the numbers behind the flight model, on screen.
    private func buildDebugOverlay() {
        let label = SKLabelNode(fontNamed: Fonts.body)
        label.fontSize = 11
        label.fontColor = .white
        label.numberOfLines = 4
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .top
        label.position = CGPoint(x: 14, y: size.height - (view?.safeAreaInsets.top ?? 0) - 96)
        label.zPosition = ZPosition.toast

        let backing = SKShapeNode(rectOf: CGSize(width: 210, height: 68), cornerRadius: 6)
        backing.fillColor = SKColor(white: 0, alpha: 0.55)
        backing.strokeColor = .clear
        backing.position = CGPoint(x: label.position.x + 100, y: label.position.y - 30)
        backing.zPosition = ZPosition.toast - 1
        addChild(backing)

        addChild(label)
        debugLabel = label
    }

    private func updateDebugOverlay() {
        guard let debugLabel else { return }
        let next = pipesNode.children.compactMap { $0 as? PipePair }
            .filter { $0.position.x > bird.position.x - 30 }
            .min { $0.position.x < $1.position.x }

        let lines = [
            "state \(state) t=" + String(format: "%.1f", elapsed),
            "y=\(Int(bird.position.y)) v=\(Int(bird.physicsBody?.velocity.dy ?? 0))",
            "pipes=\(pipesNode.children.count) nextX=\(next.map { Int($0.position.x) } ?? -1) gap=\(next.map { Int($0.gapCentre) } ?? -1)",
            "score=\(stats.score) weather=\(weatherSystem.weather.rawValue)",
        ]
        debugLabel.text = lines.joined(separator: "\n")
    }

    private var startPosition: CGPoint {
        CGPoint(x: size.width * 0.32, y: size.height * 0.62)
    }

    // MARK: - State transitions

    private func enterReadyState() {
        state = .ready
        stats = RunStats()
        stats.seed = dailyChallenge?.seed ?? SeededRandom.newSeedString()
        deathCause = .none
        powerUps.reset()
        demoPilot.reset()
        ghostRecorder.reset()
        ghostPlayer?.reset()
        weatherSystem.reset()
        elapsed = 0
        spawnAccumulator = 0
        lastUpdate = 0

        pipesNode.removeAllChildren()
        overlayNode.removeAllChildren()
        worldNode.speed = 1

        bird.prepareForNewRun(at: startPosition)
        bird.physicsBody?.isDynamic = false
        bird.startIdleBob()

        hud.setScore(0, animated: false)
        hud.setCoins(0)
        hud.setCombo(0, multiplier: 1)
        hud.setBest(store.profile.bestScore(for: mode))
        hud.setActivePowerUps([], remaining: { _ in 0 })
        if let limit = mode.timeLimit { hud.setTimeRemaining(limit) }

        let prompt = settings.hasSeenTutorial ? "TAP TO START" : "TAP TO FLAP"
        hud.flashCentreMessage(prompt, duration: 1.4)

        if mode == .daily, let challenge = dailyChallenge {
            toasts.show(challenge.summary, color: Palette.buttonFillActive)
        }

        if LaunchOptions.isDemoMode {
            // Attract mode: every ready state starts itself, including restarts,
            // so a recording never stalls waiting for a tap.
            run(
                .sequence([.wait(forDuration: 1.1), .run { [weak self] in self?.startPlaying() }]),
                withKey: "demo-autostart"
            )
        }
    }

    private func startPlaying() {
        guard state == .ready else { return }
        state = .playing
        settings.hasSeenTutorial = true

        bird.stopIdleBob()
        bird.physicsBody?.isDynamic = true
        stats.startedAt = Date()
        flap()
    }

    func pause() {
        guard state == .playing else { return }
        state = .paused
        worldNode.speed = 0
        bird.isPaused = true
        physicsWorld.speed = 0
        presentPauseOverlay()
    }

    private func resume() {
        guard state == .paused else { return }
        overlayNode.removeAllChildren()
        hud.flashCentreMessage("GO!", duration: 0.35)
        state = .playing
        worldNode.speed = slowMotionFactor
        bird.isPaused = false
        physicsWorld.speed = 1
        // Ignore the frame gap accumulated while paused.
        lastUpdate = 0
    }

    /// Called by the view controller when the app loses focus.
    func pauseForBackground() {
        if state == .playing { pause() }
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Buttons handle their own touches; only react to taps on empty space.
        if let touch = touches.first {
            let hit = nodes(at: touch.location(in: self))
            if hit.contains(where: { $0 is ButtonNode || $0.parent is ButtonNode }) { return }
        }

        switch state {
        case .ready:
            startPlaying()
        case .playing:
            flap()
        case .paused, .dying, .gameOver:
            break
        }
    }

    private func flap() {
        guard state.acceptsFlap else { return }
        bird.flap()
        AudioManager.shared.play(.flap)
        Haptics.shared.flap()
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        let delta: TimeInterval = lastUpdate == 0 ? 0 : min(1.0 / 20.0, currentTime - lastUpdate)
        lastUpdate = currentTime

        guard state == .playing || state == .ready else { return }

        bird.updateRotation()
        if LaunchOptions.showsDebugOverlay { updateDebugOverlay() }

        guard state == .playing else { return }

        elapsed += delta
        stats.endedAt = nil

        if LaunchOptions.isDemoMode { updateDemoPilot() }
        updatePowerUps(delta: delta)
        updateWeather(delta: delta)
        updateSpawning(delta: delta)
        updateMagnet()
        updateGhost(delta: delta)
        updateTimeAttack()

        bird.clampVelocity()
        bird.clampHorizontal(anchorX: startPosition.x, maxDrift: 46, deltaTime: delta)
        ghostRecorder.record(normalisedHeight: Double(bird.position.y / size.height), deltaTime: delta)
    }

    /// Auto-pilot for `-demo` recordings: aim at the next gap and flap to hold it.
    private func updateDemoPilot() {
        let birdX = bird.position.x

        // The nearest pipe pair the bird has not cleared yet.
        let upcoming = pipesNode.children
            .compactMap { $0 as? PipePair }
            .filter { $0.position.x > birdX - 30 }
            .min { $0.position.x < $1.position.x }

        // With no pipe in sight, hold a comfortable cruising height.
        let gapCentre = upcoming?.gapCentre ?? size.height * 0.5
        let gapHeight = upcoming?.gapHeight ?? currentSnapshot.pipeGap

        if demoPilot.shouldFlap(
            birdY: bird.position.y,
            gapCentre: gapCentre,
            gapHeight: gapHeight,
            verticalVelocity: bird.physicsBody?.velocity.dy ?? 0,
            now: elapsed
        ) {
            flap()
        }
    }

    private func updatePowerUps(delta: TimeInterval) {
        powerUps.expire(now: elapsed)

        let active = powerUps.activeKinds(now: elapsed)
        hud.setActivePowerUps(active) { [weak self] kind in
            guard let self else { return 0 }
            return self.powerUps.remaining(kind, now: self.elapsed)
        }

        bird.setShieldVisible(powerUps.hasShield)
        bird.setShrunk(powerUps.isActive(.shrink, now: elapsed))
        worldNode.speed = slowMotionFactor
    }

    /// Slow-motion is applied by scaling the whole scrolling world.
    private var slowMotionFactor: CGFloat {
        powerUps.isActive(.slowMotion, now: elapsed) ? GameConfig.slowMotionFactor : 1
    }

    private func updateWeather(delta: TimeInterval) {
        let force = weatherSystem.update(deltaTime: delta, elapsed: elapsed)
        if force.dx != 0 {
            bird.physicsBody?.applyImpulse(force)
        }
        if weatherSystem.weather.downdraft > 0 {
            bird.physicsBody?.applyImpulse(
                CGVector(dx: 0, dy: -weatherSystem.weather.downdraft * CGFloat(delta) * 20)
            )
        }
        stats.secondsInWind = weatherSystem.secondsInWind
    }

    private func updateSpawning(delta: TimeInterval) {
        currentSnapshot = difficulty.snapshot(pipesPassed: stats.pipesPassed)
        physicsWorld.gravity = CGVector(dx: 0, dy: currentSnapshot.gravity)

        spawnAccumulator += delta * Double(slowMotionFactor)
        guard spawnAccumulator >= currentSnapshot.spawnInterval else { return }
        spawnAccumulator = 0
        spawnPipePair()
    }

    /// Pull nearby coins toward the bird while the magnet is active.
    private func updateMagnet() {
        guard powerUps.isActive(.magnet, now: elapsed) else { return }

        for pair in pipesNode.children {
            for node in pair.children where node.name == Collectible.coinKey {
                let worldPosition = pair.convert(node.position, to: self)
                let dx = bird.position.x - worldPosition.x
                let dy = bird.position.y - worldPosition.y
                let distance = sqrt(dx * dx + dy * dy)
                guard distance < GameConfig.magnetRadius, distance > 1 else { continue }

                // Ease toward the bird; the closer it gets, the faster it moves.
                let pull = (1 - distance / GameConfig.magnetRadius) * 7
                node.position = CGPoint(
                    x: node.position.x + dx / distance * pull,
                    y: node.position.y + dy / distance * pull
                )
            }
        }
    }

    private func updateGhost(delta: TimeInterval) {
        guard var player = ghostPlayer, let node = ghostNode else { return }
        player.advance(by: delta)
        ghostPlayer = player

        if let height = player.currentHeight {
            node.position = CGPoint(x: node.position.x, y: CGFloat(height) * size.height)
            node.isHidden = false
        } else {
            node.isHidden = true
            // Outliving the ghost's recording means the player beat it.
            if player.hasFinished, stats.score > player.score {
                stats.beatOwnGhost = true
            }
        }
    }

    private func updateTimeAttack() {
        guard let limit = mode.timeLimit else { return }
        let remaining = limit - elapsed
        hud.setTimeRemaining(remaining)

        if remaining <= 0 {
            deathCause = .timeUp
            finishRun()
        } else if remaining <= 3.05, abs(remaining.rounded() - remaining) < 0.02 {
            AudioManager.shared.play(.countdown)
        }
    }

    // MARK: - Spawning

    private func spawnPipePair() {
        let groundTop = parallax.groundHeight
        let gap = currentSnapshot.pipeGap
        let margin: CGFloat = 60

        let lowest = groundTop + gap / 2 + margin
        let highest = size.height - gap / 2 - margin
        guard highest > lowest else { return }

        let centre = CGFloat(generator.nextDouble(in: Double(lowest)...Double(highest)))

        let content: PipePair.GapContent = {
            guard mode.allowsPowerUps, generator.chance(GameConfig.powerUpSpawnChance) else {
                return .coin
            }
            return .powerUp(PowerUpKind.random(using: &generator))
        }()

        // Drifting pipes start appearing once the player is clearly comfortable.
        let moving = mode.ramps && stats.pipesPassed >= 25 && generator.chance(0.22)

        let pair = PipePair.make(
            gapCentre: centre,
            gapHeight: gap,
            sceneHeight: size.height,
            content: content,
            tint: timeOfDay.worldTint,
            tintStrength: timeOfDay.worldTintStrength,
            moving: moving
        )

        let pipeWidth = SKTexture(imageNamed: "PipeUp").size().width * GameConfig.pipeScale
        pair.position = CGPoint(x: size.width + pipeWidth, y: 0)

        let distance = size.width + pipeWidth * 3
        let move = SKAction.moveBy(x: -distance, y: 0, duration: currentSnapshot.scrollRate * TimeInterval(distance))
        pair.run(.sequence([move, .removeFromParent()]))

        pipesNode.addChild(pair)
    }

    // MARK: - Contacts

    func didBegin(_ contact: SKPhysicsContact) {
        guard state == .playing else { return }

        let categories = PhysicsCategory(rawValue: contact.bodyA.categoryBitMask)
            .union(PhysicsCategory(rawValue: contact.bodyB.categoryBitMask))

        if categories.contains(.scoreGate) {
            handleScoreGate(contact)
            return
        }
        if categories.contains(.coin) {
            handleCoin(contact)
            return
        }
        if categories.contains(.powerUp) {
            handlePowerUp(contact)
            return
        }
        if categories.contains(.ceiling) {
            // The ceiling blocks but never kills — dying to an invisible wall is unfair.
            bird.physicsBody?.velocity = CGVector(dx: 0, dy: -60)
            return
        }
        if categories.contains(.pipe) {
            handleLethalContact(cause: .pipe)
            return
        }
        if categories.contains(.world) {
            handleLethalContact(cause: .ground)
        }
    }

    private func handleScoreGate(_ contact: SKPhysicsContact) {
        let gate = contact.bodyA.categoryBitMask == PhysicsCategory.scoreGate.rawValue
            ? contact.bodyA.node
            : contact.bodyB.node
        guard let pair = gate?.parent as? PipePair, !pair.hasScored else { return }
        pair.markScored()

        stats.pipesPassed += 1
        let multiplier = powerUps.isActive(.doublePoints, now: elapsed) ? 2 : 1
        stats.score += GameConfig.pointsPerPipe * multiplier

        hud.setScore(stats.score, animated: true)
        AudioManager.shared.play(.score)

        // Passing a gap without taking its coin breaks the combo.
        let coinLeftBehind = pair.children.contains { $0.name == Collectible.coinKey }
        if coinLeftBehind { stats.breakCombo() }
        hud.setCombo(stats.combo, multiplier: stats.comboMultiplier)

        advanceDayNightIfNeeded()
    }

    private func handleCoin(_ contact: SKPhysicsContact) {
        let node = contact.bodyA.categoryBitMask == PhysicsCategory.coin.rawValue
            ? contact.bodyA.node
            : contact.bodyB.node
        guard let node, node.parent != nil else { return }

        stats.registerCoin()
        hud.setCoins(stats.coins)
        hud.setCombo(stats.combo, multiplier: stats.comboMultiplier)
        Collectible.collect(node, tint: SKColor(red: 0.99, green: 0.82, blue: 0.28, alpha: 1))
        AudioManager.shared.play(.coin)
        Haptics.shared.coin()
    }

    private func handlePowerUp(_ contact: SKPhysicsContact) {
        let node = contact.bodyA.categoryBitMask == PhysicsCategory.powerUp.rawValue
            ? contact.bodyA.node
            : contact.bodyB.node
        guard let node, node.parent != nil, let kind = Collectible.kind(from: node) else { return }

        powerUps.activate(kind, now: elapsed)
        stats.powerUpsUsed = powerUps.totalCollected
        if kind == .shield { stats.usedShield = true }

        Collectible.collect(node, tint: kind.color)
        AudioManager.shared.play(.powerUp)
        Haptics.shared.powerUp()
        toasts.show("\(kind.symbol)  \(kind.displayName)", color: kind.color)
    }

    private func handleLethalContact(cause: DeathCause) {
        // A shield absorbs the hit and grants a moment of grace.
        if powerUps.consumeShield() {
            bird.setShieldVisible(powerUps.hasShield)
            bird.burstFeathers(color: PowerUpKind.shield.color)
            bird.physicsBody?.velocity = CGVector(dx: 0, dy: 120)
            AudioManager.shared.play(.powerUp)
            Haptics.shared.powerUp()
            toasts.show("🛡  Shield absorbed the hit!", color: PowerUpKind.shield.color)
            return
        }

        guard mode.isLethal else {
            // Zen mode: bounce instead of dying.
            bird.physicsBody?.velocity = CGVector(dx: 0, dy: 160)
            return
        }

        deathCause = cause
        finishRun()
    }

    // MARK: - Day/night

    private func advanceDayNightIfNeeded() {
        guard stats.pipesPassed % GameConfig.pipesPerDayNightCycle == 0 else { return }
        guard mode != .daily || dailyChallenge?.modifier != "nightfall" else { return }

        timeOfDay = timeOfDay.next
        if timeOfDay.isDark { stats.sawNight = true }

        run(.colorize(with: timeOfDay.skyColor, colorBlendFactor: 1, duration: 1.2))
        parallax.applyTint(timeOfDay.worldTint, strength: timeOfDay.worldTintStrength, animated: true)
        toasts.show("\(timeOfDay.name) falls…", color: Palette.buttonFillActive)
    }

    // MARK: - Ending a run

    private func finishRun() {
        guard state == .playing else { return }
        state = .dying
        stats.endedAt = Date()

        if stats.sawNight == false, timeOfDay.isDark { stats.sawNight = true }

        bird.enterDeathState()
        bird.burstFeathers(color: settings.selectedSkin.trailColor)
        AudioManager.shared.play(.crash)
        Haptics.shared.crash()

        pipesNode.children.forEach { $0.removeAction(forKey: "drift") }
        worldNode.speed = 0
        weatherSystem.teardown()

        if !settings.reduceFlashing && deathCause != .timeUp {
            flashScreen()
        }

        let isPersonalBest = store.record(run: stats, mode: mode, deathCause: deathCause)
        if isPersonalBest, mode != .daily {
            store.storeGhost(samples: ghostRecorder.samples, score: stats.score)
        }
        if mode == .daily, let challenge = dailyChallenge {
            store.markDailyCompleted(challenge.date)
        }

        let unlocked = achievementSystem.evaluate(run: stats, mode: mode)
        OnlineService.shared.pushAchievements()

        // Give the death animation a beat before the panel appears.
        run(.wait(forDuration: 0.85)) { [weak self] in
            self?.presentGameOver(isPersonalBest: isPersonalBest, unlocked: unlocked)
        }
    }

    private func flashScreen() {
        let overlay = flashOverlay ?? SKSpriteNode(color: .red, size: size)
        overlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.zPosition = ZPosition.weather + 1
        overlay.alpha = 0
        if overlay.parent == nil { addChild(overlay) }
        flashOverlay = overlay

        let pulse = SKAction.sequence([
            .fadeAlpha(to: 0.55, duration: GameConfig.deathFlashInterval),
            .fadeAlpha(to: 0, duration: GameConfig.deathFlashInterval),
        ])
        overlay.run(.repeat(pulse, count: GameConfig.deathFlashCount))
    }

    private func presentGameOver(isPersonalBest: Bool, unlocked: [Achievement]) {
        state = .gameOver

        for achievement in unlocked {
            toasts.show("\(achievement.icon)  \(achievement.name)", color: Palette.positive)
            AudioManager.shared.play(.achievement)
            Haptics.shared.achievement()
        }

        let summary = GameOverPanel.Summary(
            score: stats.score,
            best: store.profile.bestScore(for: mode),
            coins: stats.coins,
            pipesPassed: stats.pipesPassed,
            maxCombo: stats.maxCombo,
            duration: stats.duration,
            mode: mode,
            medal: Medal.earned(for: stats.score),
            isPersonalBest: isPersonalBest,
            cause: deathCause,
            rank: nil,
            totalPlayers: nil,
            queuedForSync: mode.isRanked && OnlineService.shared.status.isOnline == false,
            syncDetail: nil
        )

        showPanel(for: summary)

        if LaunchOptions.isDemoMode {
            run(.sequence([.wait(forDuration: 2.6), .run { [weak self] in self?.restart() }]))
        }

        // Submit in the background and refresh the panel if a rank comes back.
        guard mode.isRanked else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await OnlineService.shared.submitLatestRun()
            guard self.state == .gameOver else { return }

            var updated = summary
            updated.rank = outcome.rank
            updated.totalPlayers = outcome.totalPlayers
            updated.queuedForSync = outcome.queued
            updated.syncDetail = outcome.detail

            if outcome.flagged {
                self.toasts.show("Run flagged by fair-play checks", color: Palette.negative)
            }
            if outcome.rank != nil || outcome.queued != summary.queuedForSync || outcome.detail != nil {
                self.showPanel(for: updated)
            }
        }
    }

    private func showPanel(for summary: GameOverPanel.Summary) {
        overlayNode.removeAllChildren()
        let panel = GameOverPanel(
            summary: summary,
            width: min(size.width - 48, 340),
            onRetry: { [weak self] in self?.restart() },
            onMenu: { [weak self] in self?.returnToMenu() },
            onShare: { [weak self] in self?.share(summary: summary) }
        )
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlayNode.addChild(panel)
    }

    private func presentPauseOverlay() {
        overlayNode.removeAllChildren()

        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.55), size: size)
        dim.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlayNode.addChild(dim)

        let panel = PanelNode(size: CGSize(width: min(size.width - 64, 300), height: 250), title: "PAUSED")
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)

        let resumeButton = ButtonNode(title: "RESUME", size: CGSize(width: 220, height: 46)) { [weak self] in
            self?.resume()
        }
        resumeButton.position = CGPoint(x: 0, y: 18)
        panel.addChild(resumeButton)

        let restartButton = ButtonNode(title: "RESTART", size: CGSize(width: 220, height: 40), fontSize: 18) { [weak self] in
            self?.restart()
        }
        restartButton.position = CGPoint(x: 0, y: -34)
        panel.addChild(restartButton)

        let menuButton = ButtonNode(title: "MENU", size: CGSize(width: 220, height: 40), fontSize: 18) { [weak self] in
            self?.returnToMenu()
        }
        menuButton.position = CGPoint(x: 0, y: -84)
        panel.addChild(menuButton)

        panel.present()
        overlayNode.addChild(panel)
    }

    // MARK: - Navigation

    private func restart() {
        physicsWorld.speed = 1
        bird.isPaused = false
        configureRun()
        parallax.applyTint(timeOfDay.worldTint, strength: timeOfDay.worldTintStrength, animated: false)
        run(.colorize(with: timeOfDay.skyColor, colorBlendFactor: 1, duration: 0.2))

        let weather: Weather = {
            if let modifier = dailyChallenge?.modifier, let forced = DailyChallengeHelper.weather(for: modifier) {
                return forced
            }
            return mode == .zen ? .clear : Weather.random(using: &generator)
        }()
        weatherSystem.apply(weather, sceneSize: size, reduceMotion: reduceMotion)

        enterReadyState()
    }

    private func returnToMenu() {
        physicsWorld.speed = 1
        let menu = MenuScene(size: size)
        menu.scaleMode = .resizeFill
        view?.presentScene(menu, transition: .fade(withDuration: 0.35))
    }

    /// Offer the system share sheet with a short brag message.
    private func share(summary: GameOverPanel.Summary) {
        guard let viewController = view?.window?.rootViewController else { return }

        var text = "I scored \(summary.score) in \(summary.mode.displayName) on Flappy Bird!"
        if summary.medal != .none { text += " \(summary.medal.label) medal 🏅" }
        if let rank = summary.rank { text += " Global rank #\(rank)." }

        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = view
        viewController.present(activity, animated: true)
    }
}
