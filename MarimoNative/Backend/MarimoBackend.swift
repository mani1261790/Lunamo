import MarimoDomain

public struct ParsedNotebookCell: Sendable, Equatable {
  public let sourceID: String?
  public let code: String
  public let name: String
  public let configuration: CellConfiguration

  public init(
    sourceID: String?,
    code: String,
    name: String,
    configuration: CellConfiguration
  ) {
    self.sourceID = sourceID
    self.code = code
    self.name = name
    self.configuration = configuration
  }
}

public struct ParsedNotebook: Sendable, Equatable {
  public let cells: [ParsedNotebookCell]

  public init(cells: [ParsedNotebookCell]) {
    self.cells = cells
  }
}

public enum NotebookParseOutcome: Sendable, Equatable {
  case success(ParsedNotebook)
  case invalidSyntax(line: Int?, column: Int?)
  case convertible
}

public protocol MarimoBackend: Sendable {
  func status() async -> BackendStatus
  func start() async throws
  func parseNotebook(source: String) async throws -> NotebookParseOutcome
  func shutdown() async
}
