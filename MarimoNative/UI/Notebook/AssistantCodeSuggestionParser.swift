import Foundation

enum AssistantCodeSuggestionParser {
  static func replacement(from response: String) -> String? {
    var blocks: [String] = []
    var remainder = response[...]

    while let opening = remainder.range(of: "```") {
      let afterOpening = remainder[opening.upperBound...]
      guard let headerEnd = afterOpening.firstIndex(of: "\n") else { break }
      let language = afterOpening[..<headerEnd]
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
      let bodyStart = afterOpening.index(after: headerEnd)
      guard let closing = afterOpening[bodyStart...].range(of: "```") else { break }
      if language == "python" || language == "py" {
        var code = String(afterOpening[bodyStart..<closing.lowerBound])
        if code.hasSuffix("\n") { code.removeLast() }
        if !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          blocks.append(code)
        }
      }
      remainder = afterOpening[closing.upperBound...]
    }

    return blocks.count == 1 ? blocks[0] : nil
  }
}
