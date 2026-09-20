import Foundation

/// Deterministic pseudo-random generator (SplitMix64).
///
/// The daily challenge must produce the *same* pipe layout on every device and
/// for every player, so the level generator cannot use `arc4random`. Seeding this
/// with the challenge seed gives an identical sequence everywhere.
///
/// It is also what makes a run reproducible from its stored `seed`, which the
/// replays and shared daily challenges rely on.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // A zero state would emit a degenerate sequence.
        self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    /// Derive a generator from an arbitrary string seed (e.g. the server's hex seed).
    init(stringSeed: String) {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325 // FNV-1a offset basis
        for byte in stringSeed.utf8 {
            hash ^= UInt64(byte)
            hash = hash.multipliedReportingOverflow(by: 0x100_0000_01B3).partialValue
        }
        self.init(seed: hash)
    }

    mutating func next() -> UInt64 {
        state = state.addingReportingOverflow(0x9E37_79B9_7F4A_7C15).partialValue
        var z = state
        z = (z ^ (z >> 30)).multipliedReportingOverflow(by: 0xBF58_476D_1CE4_E5B9).partialValue
        z = (z ^ (z >> 27)).multipliedReportingOverflow(by: 0x94D0_49BB_1331_11EB).partialValue
        return z ^ (z >> 31)
    }

    /// Uniform value in `0..<1`.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Uniform value in a closed range.
    mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + nextUnit() * (range.upperBound - range.lowerBound)
    }

    /// Uniform integer in a closed range.
    mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        guard range.lowerBound < range.upperBound else { return range.lowerBound }
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    /// `true` with the given probability.
    mutating func chance(_ probability: Double) -> Bool {
        nextUnit() < probability
    }

    /// A short, human-readable seed string for a fresh run.
    static func newSeedString() -> String {
        String(UInt64.random(in: UInt64.min...UInt64.max), radix: 16)
    }
}
