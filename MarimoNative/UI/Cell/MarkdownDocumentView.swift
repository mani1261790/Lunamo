import Foundation
import SwiftUI

enum MarkdownBlock: Equatable {
  case heading(level: Int, text: String)
  case paragraph(String)
  case unorderedList([String])
  case orderedList([String])
  case quote(String)
  case code(language: String?, source: String)
  case divider
}

enum MarkdownDocumentParser {
  static func leadingHeadingLevel(_ source: String) -> Int? {
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }
      guard case .heading(let level, _) = heading(from: trimmed) else { return nil }
      return level
    }
    return nil
  }

  static func parse(_ source: String) -> [MarkdownBlock] {
    let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var blocks: [MarkdownBlock] = []
    var paragraph: [String] = []
    var index = 0

    func flushParagraph() {
      guard !paragraph.isEmpty else { return }
      blocks.append(.paragraph(paragraph.joined(separator: "\n")))
      paragraph.removeAll(keepingCapacity: true)
    }

    while index < lines.count {
      let line = lines[index]
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if trimmed.isEmpty {
        flushParagraph()
        index += 1
        continue
      }

      if trimmed.hasPrefix("```") {
        flushParagraph()
        let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        index += 1
        var code: [String] = []
        while index < lines.count,
          !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```")
        {
          code.append(lines[index])
          index += 1
        }
        if index < lines.count { index += 1 }
        blocks.append(
          .code(language: language.isEmpty ? nil : language, source: code.joined(separator: "\n")))
        continue
      }

      if let heading = heading(from: trimmed) {
        flushParagraph()
        blocks.append(heading)
        index += 1
        continue
      }

      if isDivider(trimmed) {
        flushParagraph()
        blocks.append(.divider)
        index += 1
        continue
      }

      if trimmed.hasPrefix(">") {
        flushParagraph()
        var quote: [String] = []
        while index < lines.count {
          let candidate = lines[index].trimmingCharacters(in: .whitespaces)
          guard candidate.hasPrefix(">") else { break }
          quote.append(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces))
          index += 1
        }
        blocks.append(.quote(quote.joined(separator: "\n")))
        continue
      }

      if unorderedItem(from: trimmed) != nil {
        flushParagraph()
        var items: [String] = []
        while index < lines.count,
          let item = unorderedItem(from: lines[index].trimmingCharacters(in: .whitespaces))
        {
          items.append(item)
          index += 1
        }
        blocks.append(.unorderedList(items))
        continue
      }

      if orderedItem(from: trimmed) != nil {
        flushParagraph()
        var items: [String] = []
        while index < lines.count,
          let item = orderedItem(from: lines[index].trimmingCharacters(in: .whitespaces))
        {
          items.append(item)
          index += 1
        }
        blocks.append(.orderedList(items))
        continue
      }

      paragraph.append(line)
      index += 1
    }

    flushParagraph()
    return blocks
  }

  private static func heading(from line: String) -> MarkdownBlock? {
    let count = line.prefix(while: { $0 == "#" }).count
    guard (1...6).contains(count) else { return nil }
    let remainder = line.dropFirst(count)
    guard remainder.first?.isWhitespace == true else { return nil }
    return .heading(level: count, text: remainder.trimmingCharacters(in: .whitespaces))
  }

  private static func isDivider(_ line: String) -> Bool {
    let compact = line.filter { !$0.isWhitespace }
    guard compact.count >= 3, let marker = compact.first else { return false }
    return ["-", "*", "_"].contains(String(marker)) && compact.allSatisfy { $0 == marker }
  }

  private static func unorderedItem(from line: String) -> String? {
    for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
      return String(line.dropFirst(prefix.count))
    }
    return nil
  }

  private static func orderedItem(from line: String) -> String? {
    guard let separator = line.firstIndex(of: ".") else { return nil }
    let number = line[..<separator]
    guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
    let remainder = line[line.index(after: separator)...]
    guard remainder.first?.isWhitespace == true else { return nil }
    return remainder.trimmingCharacters(in: .whitespaces)
  }
}

struct MarkdownDocumentView: View {
  let source: String

  var body: some View {
    if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      Text(localizedUI("Double-click to edit Markdown"))
        .font(.body)
        .foregroundStyle(.tertiary)
    } else {
      VStack(alignment: .leading, spacing: 12) {
        ForEach(Array(MarkdownDocumentParser.parse(source).enumerated()), id: \.offset) {
          _, block in
          blockView(block)
        }
      }
      .textSelection(.enabled)
    }
  }

  @ViewBuilder
  private func blockView(_ block: MarkdownBlock) -> some View {
    switch block {
    case .heading(let level, let text):
      Text(inlineMarkdown(text))
        .font(headingFont(level))
        .padding(.top, level == 1 ? 8 : 3)
    case .paragraph(let text):
      Text(inlineMarkdown(text))
        .font(.body)
        .lineSpacing(5)
    case .unorderedList(let items):
      VStack(alignment: .leading, spacing: 6) {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
          HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("•").foregroundStyle(.secondary)
            Text(inlineMarkdown(item)).font(.body)
          }
        }
      }
      .padding(.leading, 10)
    case .orderedList(let items):
      VStack(alignment: .leading, spacing: 6) {
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
          HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("\(index + 1).")
              .foregroundStyle(.secondary)
              .monospacedDigit()
            Text(inlineMarkdown(item)).font(.body)
          }
        }
      }
      .padding(.leading, 10)
    case .quote(let text):
      HStack(alignment: .top, spacing: 12) {
        RoundedRectangle(cornerRadius: 1)
          .fill(Color.secondary.opacity(0.45))
          .frame(width: 3)
        Text(inlineMarkdown(text))
          .font(.body)
          .foregroundStyle(.secondary)
          .lineSpacing(4)
      }
      .padding(.vertical, 2)
    case .code(let language, let source):
      VStack(alignment: .leading, spacing: 6) {
        if let language {
          Text(language.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
        }
        Text(source)
          .font(.body.monospaced())
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(12)
      .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    case .divider:
      Divider()
    }
  }

  private func inlineMarkdown(_ source: String) -> AttributedString {
    (try? AttributedString(
      markdown: source,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    )) ?? AttributedString(source)
  }

  private func headingFont(_ level: Int) -> Font {
    switch level {
    case 1: .title.weight(.semibold)
    case 2: .title2.weight(.semibold)
    case 3: .title3.weight(.semibold)
    default: .headline
    }
  }
}
