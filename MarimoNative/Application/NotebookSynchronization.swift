import Foundation
import MarimoBackend
import MarimoDomain

enum NotebookSynchronization {
  static func snapshot(_ document: NotebookDocumentState) -> NotebookSyncSnapshot {
    NotebookSyncSnapshot(
      uri: document.notebookURI,
      version: document.notebookVersion,
      metadata: notebookMetadata(document),
      cells: document.cells.map { cell(document, $0) }
    )
  }

  static func cell(_ document: NotebookDocumentState, _ cell: NotebookCellState)
    -> NotebookSyncCell
  {
    NotebookSyncCell(
      runtimeID: cell.runtimeID,
      uri: document.cellURI(cell),
      version: cell.editor.textDocumentVersion,
      text: cell.code,
      metadata: cellMetadata(cell)
    )
  }

  static func incrementalTextChange(
    cellURI: String,
    version: UInt64,
    previous: String,
    current: String
  ) -> NotebookTextChange {
    var previousStart = previous.startIndex
    var currentStart = current.startIndex
    while previousStart < previous.endIndex, currentStart < current.endIndex,
      previous[previousStart] == current[currentStart]
    {
      previous.formIndex(after: &previousStart)
      current.formIndex(after: &currentStart)
    }

    var previousEnd = previous.endIndex
    var currentEnd = current.endIndex
    while previousEnd > previousStart, currentEnd > currentStart {
      let previousCandidate = previous.index(before: previousEnd)
      let currentCandidate = current.index(before: currentEnd)
      guard previous[previousCandidate] == current[currentCandidate] else { break }
      previousEnd = previousCandidate
      currentEnd = currentCandidate
    }

    return NotebookTextChange(
      cellURI: cellURI,
      version: version,
      range: LSPRange(
        start: position(in: previous, at: previousStart),
        end: position(in: previous, at: previousEnd)
      ),
      text: String(current[currentStart..<currentEnd])
    )
  }

  static func notebookMetadata(_ document: NotebookDocumentState) -> [String: JSONValue] {
    var root = document.projectionMetadata
    var marimo = root["marimo"]?.objectValue ?? [:]
    marimo["appOptions"] = .object([
      "managed": .object([
        "autoDownload": .array(document.owned.appOptions.managed.autoDownload.map(JSONValue.string))
      ]),
      "passthrough": .object(document.owned.appOptions.passthrough),
    ])
    marimo["header"] = document.owned.header.map(JSONValue.string) ?? .null
    marimo["notebookMetadata"] = .object(document.owned.metadata)
    root["marimo"] = .object(marimo)
    return root
  }

  static func cellMetadata(_ cell: NotebookCellState) -> [String: JSONValue] {
    var root = cell.projectionMetadata
    var marimo = root["marimo"]?.objectValue ?? [:]
    var options = marimo["options"]?.objectValue ?? [:]
    options["column"] = cell.configuration.column.map { .integer(Int64($0)) } ?? .null
    options["disabled"] = .bool(cell.configuration.disabled)
    options["hide_code"] = .bool(cell.configuration.hideCode)
    marimo["name"] = .string(cell.name)
    marimo["options"] = .object(options)
    if marimo["sourceProjections"] == nil {
      marimo["sourceProjections"] = .object(["markdown": .null, "sql": .null])
    }
    root["marimo"] = .object(marimo)

    var runtime = root["marimoRuntime"]?.objectValue ?? [:]
    runtime["stableId"] = .string(cell.runtimeID.uuidString)
    runtime["state"] = .null
    root["marimoRuntime"] = .object(runtime)
    return root
  }

  private static func position(in text: String, at index: String.Index) -> LSPPosition {
    let prefix = text[..<index]
    let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
    return LSPPosition(
      line: UInt64(lines.count - 1),
      character: UInt64(lines.last?.utf16.count ?? 0)
    )
  }
}

extension JSONValue {
  fileprivate var objectValue: [String: JSONValue]? {
    guard case .object(let value) = self else { return nil }
    return value
  }
}
