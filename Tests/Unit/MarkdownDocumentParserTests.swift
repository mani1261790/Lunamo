import Testing

@testable import MarimoUI

@Suite("Markdown document blocks")
struct MarkdownDocumentParserTests {
  @Test("Parses the block Markdown used by text cells")
  func blocks() {
    let source = """
      # Heading

      A **bold** paragraph.

      - first
      - second

      1. one
      2. two

      > quoted

      ```python
      value = 1
      ```

      ---
      """

    #expect(
      MarkdownDocumentParser.parse(source) == [
        .heading(level: 1, text: "Heading"),
        .paragraph("A **bold** paragraph."),
        .unorderedList(["first", "second"]),
        .orderedList(["one", "two"]),
        .quote("quoted"),
        .code(language: "python", source: "value = 1"),
        .divider,
      ])
  }

  @Test("Keeps multiline paragraphs and ignores heading-like text without a space")
  func paragraphs() {
    #expect(
      MarkdownDocumentParser.parse("##not a heading\nsecond line") == [
        .paragraph("##not a heading\nsecond line")
      ])
  }
}
