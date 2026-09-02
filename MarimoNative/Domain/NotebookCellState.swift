import Foundation

public struct CellConfiguration: Codable, Sendable, Equatable {
  public var column: Int?
  public var disabled: Bool
  public var hideCode: Bool

  public init(column: Int? = nil, disabled: Bool = false, hideCode: Bool = false) {
    self.column = column
    self.disabled = disabled
    self.hideCode = hideCode
  }
}

public struct CellEditorState: Sendable, Equatable {
  public var textDocumentVersion: UInt64

  public init(textDocumentVersion: UInt64 = 1) {
    self.textDocumentVersion = textDocumentVersion
  }
}

public struct CellRuntimeState: Sendable, Equatable {
  public var status: ExecutionStatus
  public var stale: Bool

  public init(status: ExecutionStatus = .idle, stale: Bool = false) {
    self.status = status
    self.stale = stale
  }
}

public struct NotebookCellState: Identifiable, Sendable, Equatable {
  public let runtimeID: UUID
  public var sourceID: String?
  public var code: String
  public var name: String
  public var configuration: CellConfiguration
  public var editor: CellEditorState
  public var runtime: CellRuntimeState

  public var id: UUID { runtimeID }

  public init(
    runtimeID: UUID = UUID(),
    sourceID: String? = nil,
    code: String = "",
    name: String = "_",
    configuration: CellConfiguration = CellConfiguration(),
    editor: CellEditorState = CellEditorState(),
    runtime: CellRuntimeState = CellRuntimeState()
  ) {
    self.runtimeID = runtimeID
    self.sourceID = sourceID
    self.code = code
    self.name = name
    self.configuration = configuration
    self.editor = editor
    self.runtime = runtime
  }
}
