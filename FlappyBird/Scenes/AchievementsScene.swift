import SpriteKit

/// Achievement list with progress, split into unlocked and locked.
final class AchievementsScene: ListScene {

    override var screenTitle: String { "ACHIEVEMENTS" }
    override var segments: [String] { ["ALL", "UNLOCKED", "LOCKED"] }
    override var rowHeight: CGFloat { 52 }

    override func buildContent() {
        let store = GameStore.shared
        let unlockedCount = AchievementCatalog.all.filter { store.progress(for: $0.code).isUnlocked }.count
        let points = AchievementCatalog.all
            .filter { store.progress(for: $0.code).isUnlocked }
            .reduce(0) { $0 + $1.points }

        let filtered = AchievementCatalog.all.filter { achievement in
            let unlocked = store.progress(for: achievement.code).isUnlocked
            switch selectedSegment {
            case 1: return unlocked
            case 2: return !unlocked
            default: return true
            }
        }

        var rows: [SKNode] = [
            makeRow(
                badge: "🏆",
                title: "\(unlockedCount) of \(AchievementCatalog.all.count) unlocked",
                subtitle: "\(points) of \(AchievementCatalog.totalPoints) points",
                value: "\(Int(Double(unlockedCount) / Double(AchievementCatalog.all.count) * 100))%",
                valueColor: Palette.accent,
                highlighted: true
            ),
        ]

        rows += filtered.map { achievement -> SKNode in
            let progress = store.progress(for: achievement.code)
            let unlocked = progress.isUnlocked

            // Secret achievements stay hidden until earned.
            let title = achievement.secret && !unlocked ? "??? (secret)" : achievement.name
            let detail = achievement.secret && !unlocked
                ? "Keep playing to discover this one."
                : achievement.detail

            let subtitle: String = {
                guard !unlocked, achievement.threshold > 1 else { return detail }
                return "\(detail)  (\(min(progress.progress, achievement.threshold))/\(achievement.threshold))"
            }()

            return makeRow(
                badge: unlocked ? achievement.icon : "🔒",
                title: title,
                subtitle: subtitle,
                value: "\(achievement.points)p",
                valueColor: unlocked ? Palette.positive : Palette.secondaryText
            )
        }

        setRows(rows)
    }
}
