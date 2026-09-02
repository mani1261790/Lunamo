import MarimoDomain

public enum ParseNotebookResult: Codable, Sendable, Equatable {
  case success(OwnedNotebookDocumentV1)
  case invalidSyntax(line: Int?, column: Int?)
  case convertible

  enum CodingKeys: String, CodingKey { case kind, document, line, column }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(String.self, forKey: .kind) {
    case "success":
      self = .success(try container.decode(OwnedNotebookDocumentV1.self, forKey: .document))
    case "invalid-syntax":
      self = .invalidSyntax(
        line: try container.decodeIfPresent(Int.self, forKey: .line),
        column: try container.decodeIfPresent(Int.self, forKey: .column)
      )
    case "convertible":
      self = .convertible
    case let kind:
      throw DecodingError.dataCorruptedError(
        forKey: .kind, in: container, debugDescription: "Unknown parse result: \(kind)")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .success(let document):
      try container.encode("success", forKey: .kind)
      try container.encode(document, forKey: .document)
    case .invalidSyntax(let line, let column):
      try container.encode("invalid-syntax", forKey: .kind)
      try container.encodeIfPresent(line, forKey: .line)
      try container.encodeIfPresent(column, forKey: .column)
    case .convertible:
      try container.encode("convertible", forKey: .kind)
    }
  }
}

public struct PrintNotebookResult: Codable, Sendable, Equatable {
  public let source: String
  public init(source: String) { self.source = source }
}
