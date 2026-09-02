import Foundation

public enum PythonSyntaxKind: Sendable, Equatable {
  case keyword
  case string
  case comment
  case number
}

public struct PythonSyntaxSpan: Sendable, Equatable {
  public let location: Int
  public let length: Int
  public let kind: PythonSyntaxKind

  public init(location: Int, length: Int, kind: PythonSyntaxKind) {
    self.location = location
    self.length = length
    self.kind = kind
  }
}

public actor PythonIncrementalHighlighter {
  private static let keywords: Set<String> = [
    "False", "None", "True", "and", "as", "assert", "async", "await", "break", "case",
    "class", "continue", "def", "del", "elif", "else", "except", "finally", "for", "from",
    "global", "if", "import", "in", "is", "lambda", "match", "nonlocal", "not", "or",
    "pass", "raise", "return", "try", "while", "with", "yield",
  ]

  private var source = ""
  private var cachedSpans: [PythonSyntaxSpan] = []
  private var lineCache: [String: [PythonSyntaxSpan]] = [:]
  private var parsedLines = 0

  public init() {}

  public func update(source newSource: String) -> [PythonSyntaxSpan] {
    guard newSource != source else { return cachedSpans }
    source = newSource
    let lines = newSource.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var offset = 0
    cachedSpans = lines.flatMap { line -> [PythonSyntaxSpan] in
      let relative: [PythonSyntaxSpan]
      if let cached = lineCache[line] {
        relative = cached
      } else {
        relative = Self.parseLine(line)
        lineCache[line] = relative
        parsedLines += 1
      }
      defer { offset += UTF16Text(line).length + 1 }
      return relative.map {
        PythonSyntaxSpan(location: offset + $0.location, length: $0.length, kind: $0.kind)
      }
    }
    let liveLines = Set(lines)
    lineCache = lineCache.filter { liveLines.contains($0.key) }
    return cachedSpans
  }

  public func parsedLineCount() -> Int { parsedLines }

  private static func parseLine(_ line: String) -> [PythonSyntaxSpan] {
    let text = UTF16Text(line)
    var spans: [PythonSyntaxSpan] = []
    var index = 0
    while index < text.length {
      let character = text.character(at: index)
      if character == 35 {
        let start = index
        while index < text.length, text.character(at: index) != 10 { index += 1 }
        spans.append(PythonSyntaxSpan(location: start, length: index - start, kind: .comment))
        continue
      }
      if character == 34 || character == 39 {
        let quote = character
        let start = index
        index += 1
        while index < text.length {
          let current = text.character(at: index)
          index += 1
          if current == 92, index < text.length {
            index += 1
          } else if current == quote {
            break
          }
        }
        spans.append(PythonSyntaxSpan(location: start, length: index - start, kind: .string))
        continue
      }
      if isDigit(character) {
        let start = index
        while index < text.length {
          let current = text.character(at: index)
          guard isDigit(current) || current == 46 || current == 95 else { break }
          index += 1
        }
        spans.append(PythonSyntaxSpan(location: start, length: index - start, kind: .number))
        continue
      }
      if isIdentifierStart(character) {
        let start = index
        index += 1
        while index < text.length, isIdentifierContinue(text.character(at: index)) { index += 1 }
        let word = text.substring(with: NSRange(location: start, length: index - start))
        if keywords.contains(word) {
          spans.append(PythonSyntaxSpan(location: start, length: index - start, kind: .keyword))
        }
        continue
      }
      index += 1
    }
    return spans
  }

  private static func isDigit(_ value: unichar) -> Bool {
    value >= 48 && value <= 57
  }

  private static func isIdentifierStart(_ value: unichar) -> Bool {
    value == 95 || (value >= 65 && value <= 90) || (value >= 97 && value <= 122)
  }

  private static func isIdentifierContinue(_ value: unichar) -> Bool {
    isIdentifierStart(value) || isDigit(value)
  }
}
