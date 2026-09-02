import Foundation
import MarimoDomain
import MarimoProcess
import MarimoProtocol

public actor MarimoLSPAdapter: MarimoBackend {
  public enum SynchronizationError: Error, Sendable, Equatable {
    case versionOverflow(UInt64)
  }

  private let connection: JSONRPCConnection
  private let launchRequest: ProcessLaunchRequest
  private var backendStatus: BackendStatus = .unavailable
  private var openNotebookCells: [String: [String]] = [:]

  public init(
    sidecarDirectory: URL,
    connection: JSONRPCConnection = JSONRPCConnection()
  ) throws {
    self.connection = connection
    launchRequest = try SidecarLaunchRequest.make(sidecarDirectory: sidecarDirectory)
  }

  public func status() async -> BackendStatus {
    guard await connection.currentState() == .ready else { return .unavailable }
    return backendStatus
  }

  public func start() async throws {
    if await connection.currentState() == .ready {
      backendStatus = .ready
      return
    }
    _ = try await connection.startAndInitialize(request: launchRequest)
    backendStatus = .ready
  }

  public func parseNotebook(source: String) async throws -> NotebookParseOutcome {
    guard backendStatus == .ready else { throw JSONRPCConnectionError.notInitialized }
    let command = MarimoCommand.parseNotebook(source: source)
    let params = try encodeAsJSONValue(command)
    let result = try await connection.request(method: "marimo/command", params: params)
    let parsed = try decode(ParseNotebookResult.self, from: result)
    switch parsed {
    case .success(let document):
      return .success(ParsedNotebook(owned: document))
    case .invalidSyntax(let line, let column):
      return .invalidSyntax(line: line, column: column)
    case .convertible:
      return .convertible
    }
  }

  public func didOpenNotebook(_ snapshot: NotebookSyncSnapshot) async throws {
    if let alreadyOpen = openNotebookCells[snapshot.uri] {
      try await didCloseNotebook(uri: snapshot.uri, cellURIs: alreadyOpen)
    }
    let params: JSONValue = .object([
      "notebookDocument": try notebookDocument(snapshot),
      "cellTextDocuments": .array(try snapshot.cells.map(textDocumentItem)),
    ])
    try await connection.notify(method: "notebookDocument/didOpen", params: params)
    openNotebookCells[snapshot.uri] = snapshot.cells.map(\.uri)
  }

  public func didChangeNotebook(
    uri: String,
    version: UInt64,
    change: NotebookSyncChange
  ) async throws {
    let changeValue: JSONValue
    switch change {
    case .text(let textChange):
      var contentChange: [String: JSONValue] = ["text": .string(textChange.text)]
      if let range = textChange.range {
        contentChange["range"] = rangeValue(range)
      }
      changeValue = .object([
        "cells": .object([
          "textContent": .array([
            .object([
              "document": .object([
                "uri": .string(textChange.cellURI),
                "version": try integer(textChange.version),
              ]),
              "changes": .array([.object(contentChange)]),
            ])
          ])
        ])
      ])
    case .structure(let structure):
      changeValue = .object([
        "cells": .object([
          "structure": .object([
            "array": .object([
              "start": try integer(structure.start),
              "deleteCount": try integer(structure.deleteCount),
              "cells": .array(structure.cells.map(notebookCell)),
            ]),
            "didOpen": .array(try structure.didOpen.map(textDocumentItem)),
            "didClose": .array(
              structure.didClose.map { .object(["uri": .string($0)]) }
            ),
          ])
        ])
      ])
      var current = openNotebookCells[uri] ?? []
      let start = min(Int(structure.start), current.count)
      let end = min(start + Int(structure.deleteCount), current.count)
      current.replaceSubrange(start..<end, with: structure.cells.map(\.uri))
      openNotebookCells[uri] = current
    case .cellData(let cells):
      changeValue = .object([
        "cells": .object(["data": .array(cells.map(notebookCell))])
      ])
    case .notebookMetadata(let metadata):
      changeValue = .object(["metadata": .object(metadata)])
    }
    try await connection.notify(
      method: "notebookDocument/didChange",
      params: .object([
        "notebookDocument": .object([
          "uri": .string(uri),
          "version": try integer(version),
        ]),
        "change": changeValue,
      ])
    )
  }

  public func didSaveNotebook(uri: String) async throws {
    try await connection.notify(
      method: "notebookDocument/didSave",
      params: .object(["notebookDocument": .object(["uri": .string(uri)])])
    )
  }

  public func didCloseNotebook(uri: String, cellURIs: [String]) async throws {
    try await connection.notify(
      method: "notebookDocument/didClose",
      params: .object([
        "notebookDocument": .object(["uri": .string(uri)]),
        "cellTextDocuments": .array(
          cellURIs.map { .object(["uri": .string($0)]) }
        ),
      ])
    )
    openNotebookCells.removeValue(forKey: uri)
  }

  public func deleteCell(
    notebookURI: String,
    kernelSessionID: String,
    cellID: String
  ) async throws {
    let command = MarimoCommand.deleteCell(
      SessionCellCommand(
        notebookURI: notebookURI,
        kernelSessionID: kernelSessionID,
        cellID: cellID
      )
    )
    _ = try await connection.request(
      method: "marimo/command",
      params: try encodeAsJSONValue(command)
    )
  }

  public func execute(
    notebookURI: String,
    executable: String,
    workingDirectory: String,
    cells: [NotebookExecutionCell]
  ) async throws {
    let command = MarimoCommand.execute(
      ExecuteCommand(
        notebookURI: notebookURI,
        executable: executable,
        workingDirectory: workingDirectory,
        cells: cells.map { CellExecution(cellID: $0.runtimeID.uuidString, code: $0.code) }
      )
    )
    _ = try await connection.request(
      method: "marimo/command",
      params: try encodeAsJSONValue(command)
    )
  }

  public func shutdown() async {
    await connection.shutdown()
    backendStatus = .unavailable
    openNotebookCells.removeAll()
  }

  private func notebookDocument(_ snapshot: NotebookSyncSnapshot) throws -> JSONValue {
    .object([
      "uri": .string(snapshot.uri),
      "notebookType": .string("marimo-notebook"),
      "version": try integer(snapshot.version),
      "cells": .array(snapshot.cells.map(notebookCell)),
      "metadata": .object(snapshot.metadata),
    ])
  }

  private func notebookCell(_ cell: NotebookSyncCell) -> JSONValue {
    .object([
      "kind": .integer(2),
      "document": .string(cell.uri),
      "metadata": .object(cell.metadata),
    ])
  }

  private func textDocumentItem(_ cell: NotebookSyncCell) throws -> JSONValue {
    .object([
      "uri": .string(cell.uri),
      "languageId": .string("python"),
      "version": try integer(cell.version),
      "text": .string(cell.text),
    ])
  }

  private func rangeValue(_ range: LSPRange) -> JSONValue {
    .object([
      "start": positionValue(range.start),
      "end": positionValue(range.end),
    ])
  }

  private func positionValue(_ position: LSPPosition) -> JSONValue {
    .object([
      "line": .integer(Int64(position.line)),
      "character": .integer(Int64(position.character)),
    ])
  }

  private func integer(_ value: UInt64) throws -> JSONValue {
    guard value <= UInt64(Int64.max) else { throw SynchronizationError.versionOverflow(value) }
    return .integer(Int64(value))
  }

  private func encodeAsJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
  }

  private func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
    try JSONDecoder().decode(type, from: JSONEncoder().encode(value))
  }
}
