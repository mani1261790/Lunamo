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
  public var lastSynchronizedCode: String
  public var hasMarkedText: Bool

  public init(
    textDocumentVersion: UInt64 = 1,
    lastSynchronizedCode: String = "",
    hasMarkedText: Bool = false
  ) {
    self.textDocumentVersion = textDocumentVersion
    self.lastSynchronizedCode = lastSynchronizedCode
    self.hasMarkedText = hasMarkedText
  }
}

public struct CellRuntimeState: Sendable, Equatable {
  public var status: ExecutionStatus
  public var stale: Bool
  public var output: JSONValue?
  public var console: [JSONValue]
  public var lastExecutedCode: String?
  public var widgetIDs: [UUID]

  public init(
    status: ExecutionStatus = .idle,
    stale: Bool = false,
    output: JSONValue? = nil,
    console: [JSONValue] = [],
    lastExecutedCode: String? = nil,
    widgetIDs: [UUID] = []
  ) {
    self.status = status
    self.stale = stale
    self.output = output
    self.console = console
    self.lastExecutedCode = lastExecutedCode
    self.widgetIDs = widgetIDs
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
  public var projectionMetadata: [String: JSONValue]

  public var id: UUID { runtimeID }

  public init(
    runtimeID: UUID = UUID(),
    sourceID: String? = nil,
    code: String = "",
    name: String = "_",
    configuration: CellConfiguration = CellConfiguration(),
    editor: CellEditorState? = nil,
    runtime: CellRuntimeState = CellRuntimeState(),
    projectionMetadata: [String: JSONValue] = [:]
  ) {
    self.runtimeID = runtimeID
    self.sourceID = sourceID
    self.code = code
    self.name = name
    self.configuration = configuration
    self.editor = editor ?? CellEditorState(lastSynchronizedCode: code)
    self.runtime = runtime
    self.projectionMetadata = projectionMetadata
  }
}
