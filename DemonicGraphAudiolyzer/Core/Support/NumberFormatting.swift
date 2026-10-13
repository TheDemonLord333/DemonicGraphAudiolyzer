import Foundation

/// German number formatting for read-outs and axis labels, and lenient parsing of user input
/// (accepts both "0,5" and "0.5").
enum NumberText {
    static let locale = Locale(identifier: "de_DE")

    static func decimal(_ value: Double, fractionDigits: Int) -> String {
        guard value.isFinite else { return "–" }
        let digits = max(0, min(fractionDigits, 10))
        let normalized = abs(value) < 0.5 * pow(10, -Double(digits)) ? 0 : value
        return normalized.formatted(.number.locale(locale).precision(.fractionLength(digits)).grouping(.never))
    }

    /// Compact representation with up to `significant` significant digits (e.g. axis labels).
    static func compact(_ value: Double, maximumFractionDigits: Int = 3) -> String {
        guard value.isFinite else { return "–" }
        if abs(value) >= 1e6 || (abs(value) < 1e-4 && value != 0) {
            return value.formatted(.number.locale(locale).notation(.scientific).precision(.significantDigits(3)))
        }
        return value.formatted(.number.locale(locale).precision(.fractionLength(0...maximumFractionDigits)).grouping(.never))
    }

    static func frequency(_ hertz: Double) -> String {
        if hertz >= 1000 {
            return decimal(hertz / 1000, fractionDigits: 2) + " kHz"
        }
        return decimal(hertz, fractionDigits: hertz < 100 ? 1 : 0) + " Hz"
    }

    static func seconds(_ value: Double) -> String {
        decimal(value, fractionDigits: value < 10 ? 1 : 0) + " s"
    }

    static func clock(_ seconds: Double) -> String {
        let total = max(0, seconds)
        let minutes = Int(total) / 60
        let rest = total - Double(minutes * 60)
        let secondsText = decimal(rest, fractionDigits: 1)
        let padded = rest < 10 ? "0" + secondsText : secondsText
        return "\(minutes):\(padded)"
    }

    /// Parses "1,5", "1.5", "-2", "  3 ", "π", "2pi" (simple constant expressions via the formula parser).
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        if let value = Double(normalized), value.isFinite {
            return value
        }
        // Allow constant expressions such as "2pi" or "-pi/2".
        if case .success(let formula) = ParsedFormula.parse(normalized), !formula.usesX, formula.usedParameters.isEmpty {
            let value = formula.root.evaluate(x: 0, parameters: FormulaParameters())
            return value.isFinite ? value : nil
        }
        return nil
    }
}
