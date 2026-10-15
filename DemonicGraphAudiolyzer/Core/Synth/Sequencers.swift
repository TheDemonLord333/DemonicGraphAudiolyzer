import Foundation

/// Fibonacci residues computed directly modulo m – never the (huge) Fibonacci numbers.
struct FibonacciModulo: Sequence, IteratorProtocol, Sendable {
    let modulus: Int
    private var current = 0
    private var upcoming = 1

    init(modulus: Int) {
        self.modulus = Swift.max(1, modulus)
        self.current = 0
        self.upcoming = 1 % self.modulus
    }

    /// F(0) mod m, F(1) mod m, F(2) mod m, …
    mutating func next() -> Int? {
        let value = current
        let following = (current + upcoming) % modulus
        current = upcoming
        upcoming = following
        return value
    }

    /// F(index) mod m without overflow (fast doubling on residues).
    static func value(at index: Int, modulus: Int) -> Int {
        let m = Swift.max(1, modulus)
        func doubling(_ n: Int) -> (Int, Int) {
            if n == 0 { return (0, 1 % m) }
            let (a, b) = doubling(n / 2)
            // F(2k) = F(k)·(2F(k+1) − F(k)), F(2k+1) = F(k)² + F(k+1)²
            let c = (a * (((2 * b) % m - a + m) % m)) % m
            let d = (a * a + b * b) % m
            return n % 2 == 0 ? (c, d) : (d, (c + d) % m)
        }
        return doubling(Swift.max(0, index)).0
    }

    /// Pisano period π(m): the residue sequence repeats with this length.
    static func pisanoPeriod(modulus: Int) -> Int {
        let m = Swift.max(1, modulus)
        if m == 1 { return 1 }
        var previous = 0
        var current = 1
        for index in 1...(6 * m) {
            (previous, current) = (current, (previous + current) % m)
            if previous == 0, current == 1 { return index }
        }
        return 6 * m
    }
}

/// Parity of binomial coefficients without factorials (Lucas' theorem):
/// C(n, k) is odd exactly when every bit of k is also set in n, i.e. (k & n) == k.
enum PascalParity {
    static func isOdd(row: Int, position: Int) -> Bool {
        guard row >= 0, position >= 0, position <= row else { return false }
        return position & row == position
    }

    /// Positions k of row n with odd C(n, k).
    static func oddPositions(row: Int) -> [Int] {
        guard row >= 0 else { return [] }
        return (0...row).filter { isOdd(row: row, position: $0) }
    }

    /// Up to `limit` positions spread evenly over the odd positions (voice limit).
    static func limitedPositions(row: Int, limit: Int) -> [Int] {
        let odd = oddPositions(row: row)
        guard odd.count > limit, limit > 0 else { return odd }
        if limit == 1 { return [odd[odd.count / 2]] }
        return (0..<limit).map { index in
            odd[Int((Double(index) * Double(odd.count - 1) / Double(limit - 1)).rounded())]
        }
    }
}

enum FifthsSequence {
    static let majorScale: [Double] = [0, 2, 4, 5, 7, 9, 11]

    /// Circle of fifths (chromatic): pitch class mod(7n, 12) in semitones.
    static func pitchClass(step: Int) -> Int {
        Int(MathSemantics.modulo(Double(7 * step), 12))
    }

    /// Diatonic sequence of fifths: scale degree mod(4n, 7) – a different procedure.
    static func diatonicDegree(step: Int) -> Int {
        Int(MathSemantics.modulo(Double(4 * step), 7))
    }

    static func diatonicSemitones(step: Int) -> Double {
        majorScale[diatonicDegree(step: step)]
    }
}

/// Rhythm patterns like "x..x o.x." (x or X = hit, o = quiet hit with half velocity,
/// . or - = rest; spaces and | are ignored).
struct RhythmPattern: Equatable, Sendable {
    /// nil = rest, otherwise the velocity.
    let steps: [Double?]

    init(_ text: String) {
        var steps: [Double?] = []
        for character in text {
            switch character {
            case "x", "X", "1": steps.append(1)
            case "o", "O": steps.append(0.5)
            case ".", "-", "_", "0": steps.append(nil)
            default: break
            }
        }
        self.steps = steps.isEmpty ? [1] : steps
    }

    var hitCount: Int { steps.compactMap { $0 }.count }
}
