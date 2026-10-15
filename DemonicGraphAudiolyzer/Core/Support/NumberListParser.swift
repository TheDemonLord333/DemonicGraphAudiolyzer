import Foundation

/// Lenient parsing of number lists typed by the user: "0; 3; 7", "0 3 7", "0, 3, 7",
/// "[0, 3, 7]", "0,5; 1,5" (German decimal comma) and constant expressions such as "2pi".
enum NumberListParser {
    static func parse(_ text: String) -> [Double]? {
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("[") && normalized.hasSuffix("]") {
            normalized = String(normalized.dropFirst().dropLast())
        }
        guard !normalized.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if !normalized.contains(";") {
            if normalized.contains(", ") {
                // "0, 3, 7": comma followed by a space separates.
                normalized = normalized.replacingOccurrences(of: ", ", with: ";")
            } else if normalized.filter({ $0 == "," }).count > 1, !normalized.contains(where: \.isWhitespace) {
                // "0,3,7": several commas without any spaces are separators, not decimal commas.
                normalized = normalized.replacingOccurrences(of: ",", with: ";")
            }
        }
        let parts = normalized.split { $0 == ";" || $0 == " " || $0 == "\n" || $0 == "\t" }.map(String.init)
        var values: [Double] = []
        for part in parts where !part.isEmpty {
            guard let value = NumberText.parse(part), value.isFinite else { return nil }
            values.append(value)
        }
        return values.isEmpty ? nil : values
    }
}
