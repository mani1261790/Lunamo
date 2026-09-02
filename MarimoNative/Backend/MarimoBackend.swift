import Foundation
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
  public let owned: OwnedNotebookDocumentV1

  public init(cells: [ParsedNotebookCell]) {
    owned = OwnedNotebookDocumentV1(
      cells: cells.map { cell in
        OwnedNotebookCell(
          id: cell.sourceID,
          code: cell.code,
          name: cell.name,
          config: OwnedNotebookCellConfig(
            column: cell.configuration.column,
            disabled: cell.configuration.disabled,
            hideCode: cell.configuration.hideCode
          )
        )
      }
    )
  }

  public init(owned: OwnedNotebookDocumentV1) {
    self.owned = owned
  }

  public var cells: [ParsedNotebookCell] {
    owned.cells.map { cell in
      ParsedNotebookCell(
        sourceID: cell.id,
        code: cell.code ?? "",
        name: (cell.name?.isEmpty == false ? cell.name : nil) ?? "_",
        configuration: CellConfiguration(
          column: cell.config.column,
          disabled: cell.config.disabled ?? false,
          hideCode: cell.config.hideCode ?? false
        )
      )
    }
  }
}

public struct LSPPosition: Codable, Sendable, Equatable {
  public let line: UInt64
  public let character: UInt64

  public init(line: UInt64, character: UInt64) {
    self.line = line
    self.character = character
  }
}

public struct LSPRange: Codable, Sendable, Equatable {
  public let start: LSPPosition
  public let end: LSPPosition

  public init(start: LSPPosition, end: LSPPosition) {
    self.start = start
    self.end = end
  }
}

public struct NotebookTextChange: Codable, Sendable, Equatable {
  public let cellURI: String
  public let version: UInt64
  public let range: LSPRange?
  public let text: String

  public init(cellURI: String, version: UInt64, range: LSPRange?, text: String) {
    self.cellURI = cellURI
    self.version = version
    self.range = range
    self.text = text
  }
}

public struct NotebookSyncCell: Codable, Sendable, Equatable {
  public let runtimeID: UUID
  public let uri: String
  public let version: UInt64
  public let text: String
  public let metadata: [String: JSONValue]

  public init(
    runtimeID: UUID,
    uri: String,
    version: UInt64,
    text: String,
    metadata: [String: JSONValue]
  ) {
    self.runtimeID = runtimeID
    self.uri = uri
    self.version = version
    self.text = text
    self.metadata = metadata
  }
}

public struct NotebookSyncSnapshot: Codable, Sendable, Equatable {
  public let uri: String
  public let version: UInt64
  public let metadata: [String: JSONValue]
  public let cells: [NotebookSyncCell]

  public init(
    uri: String,
    version: UInt64,
    metadata: [String: JSONValue],
    cells: [NotebookSyncCell]
  ) {
    self.uri = uri
    self.version = version
    self.metadata = metadata
    self.cells = cells
  }
}

public struct NotebookStructureChange: Codable, Sendable, Equatable {
  public let start: UInt64
  public let deleteCount: UInt64
  public let cells: [NotebookSyncCell]
  public let didOpen: [NotebookSyncCell]
  public let didClose: [String]

  public init(
    start: UInt64,
    deleteCount: UInt64,
    cells: [NotebookSyncCell],
    didOpen: [NotebookSyncCell] = [],
    didClose: [String] = []
  ) {
    self.start = start
    self.deleteCount = deleteCount
    self.cells = cells
    self.didOpen = didOpen
    self.didClose = didClose
  }
}

public enum NotebookSyncChange: Sendable, Equatable {
  case text(NotebookTextChange)
  case structure(NotebookStructureChange)
  case cellData([NotebookSyncCell])
  case notebookMetadata([String: JSONValue])
}

public struct NotebookExecutionCell: Sendable, Equatable {
  public let runtimeID: UUID
  public let code: String

  public init(runtimeID: UUID, code: String) {
    self.runtimeID = runtimeID
    self.code = code
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
  func didOpenNotebook(_ snapshot: NotebookSyncSnapshot) async throws
  func didChangeNotebook(uri: String, version: UInt64, change: NotebookSyncChange) async throws
  func didSaveNotebook(uri: String) async throws
  func didCloseNotebook(uri: String, cellURIs: [String]) async throws
  func deleteCell(notebookURI: String, kernelSessionID: String, cellID: String) async throws
  func execute(
    notebookURI: String,
    executable: String,
    workingDirectory: String,
    cells: [NotebookExecutionCell]
  ) async throws
  func shutdown() async
}

extension MarimoBackend {
  public func didOpenNotebook(_: NotebookSyncSnapshot) async throws {}
  public func didChangeNotebook(
    uri _: String,
    version _: UInt64,
    change _: NotebookSyncChange
  ) async throws {}
  public func didSaveNotebook(uri _: String) async throws {}
  public func didCloseNotebook(uri _: String, cellURIs _: [String]) async throws {}
  public func deleteCell(
    notebookURI _: String,
    kernelSessionID _: String,
    cellID _: String
  ) async throws {}
  public func execute(
    notebookURI _: String,
    executable _: String,
    workingDirectory _: String,
    cells _: [NotebookExecutionCell]
  ) async throws {}
}
