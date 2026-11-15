import Foundation

/// Transient view of Python source, produced only by the bundled Python parser.
public struct TextCellProjection: Codable, Sendable, Equatable {
  public let source: String
  public let markdown: String?

  public init(source: String, markdown: String?) {
    self.source = source
    self.markdown = markdown
  }
}
