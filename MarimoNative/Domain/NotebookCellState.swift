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
  public var output: MarimoOutput?
  public var console: [MarimoOutput]
  public var lastExecutedCode: String?
  public var widgetIDs: [String]
  public var stdinPrompt: StdinPromptState?

  public init(
    status: ExecutionStatus = .idle,
    stale: Bool = false,
    output: MarimoOutput? = nil,
    console: [MarimoOutput] = [],
    lastExecutedCode: String? = nil,
    widgetIDs: [String] = [],
    stdinPrompt: StdinPromptState? = nil
  ) {
    self.status = status
    self.stale = stale
    self.output = output
    self.console = console
    self.lastExecutedCode = lastExecutedCode
    self.widgetIDs = widgetIDs
    self.stdinPrompt = stdinPrompt
  }
}

public struct StdinPromptState: Sendable, Equatable {
  public let prompt: String
  public let password: Bool
  public var submitted: Bool

  public init(prompt: String, password: Bool, submitted: Bool = false) {
    self.prompt = prompt
    self.password = password
    self.submitted = submitted
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
