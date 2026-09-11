import Foundation

/// Returns the first capture group of the first match, or nil.
func firstCapture(_ pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          match.numberOfRanges > 1,
          let range = Range(match.range(at: 1), in: text)
    else { return nil }
    return String(text[range])
}
