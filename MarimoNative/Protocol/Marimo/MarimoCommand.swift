import MarimoDomain

public struct CellExecution: Codable, Sendable, Equatable {
  public let cellID: String
  public let code: String
  enum CodingKeys: String, CodingKey {
    case cellID = "cellId"
    case code
  }
  public init(cellID: String, code: String) {
    self.cellID = cellID
    self.code = code
  }
}

public struct ExecuteCommand: Codable, Sendable, Equatable {
  public let notebookURI: String
  public let executable: String
  public let workingDirectory: String
  public let cells: [CellExecution]
  enum CodingKeys: String, CodingKey {
    case notebookURI = "notebookUri"
    case executable, workingDirectory, cells
  }
  public init(
    notebookURI: String, executable: String, workingDirectory: String, cells: [CellExecution]
  ) {
    self.notebookURI = notebookURI
    self.executable = executable
    self.workingDirectory = workingDirectory
    self.cells = cells
  }
}

public struct UpdateUIElementCommand: Codable, Sendable, Equatable {
  public let notebookURI: String
  public let kernelSessionID: String
  public let objectIDs: [String]
  public let values: [JSONValue]
  public let request: [String: JSONValue]?
  public let token: String?
  enum CodingKeys: String, CodingKey {
    case notebookURI = "notebookUri"
    case kernelSessionID = "kernelSessionId"
    case objectIDs = "objectIds"
    case values, request, token
  }
  public init(
    notebookURI: String, kernelSessionID: String, objectIDs: [String], values: [JSONValue],
    request: [String: JSONValue]? = nil, token: String? = nil
  ) {
    self.notebookURI = notebookURI
    self.kernelSessionID = kernelSessionID
    self.objectIDs = objectIDs
    self.values = values
    self.request = request
    self.token = token
  }

  public func validate() throws {
    guard objectIDs.count == values.count else {
      throw UpdateUIElementCommandError.countMismatch(
        objectIDs: objectIDs.count,
        values: values.count
      )
    }
  }
}

public enum UpdateUIElementCommandError: Error, Sendable, Equatable {
  case countMismatch(objectIDs: Int, values: Int)
}

public struct SessionCellCommand: Codable, Sendable, Equatable {
  public let notebookURI: String
  public let kernelSessionID: String
  public let cellID: String
  enum CodingKeys: String, CodingKey {
    case notebookURI = "notebookUri"
    case kernelSessionID = "kernelSessionId"
    case cellID = "cellId"
  }
  public init(notebookURI: String, kernelSessionID: String, cellID: String) {
    self.notebookURI = notebookURI
    self.kernelSessionID = kernelSessionID
    self.cellID = cellID
  }
}

public struct SendStdinCommand: Codable, Sendable, Equatable {
  public let notebookURI: String
  public let kernelSessionID: String
  public let text: String
  enum CodingKeys: String, CodingKey {
    case notebookURI = "notebookUri"
    case kernelSessionID = "kernelSessionId"
    case text
  }
  public init(notebookURI: String, kernelSessionID: String, text: String) {
    self.notebookURI = notebookURI
    self.kernelSessionID = kernelSessionID
    self.text = text
  }
}

public struct NotebookURICommand: Codable, Sendable, Equatable {
  public let notebookURI: String
  enum CodingKeys: String, CodingKey { case notebookURI = "notebookUri" }
  public init(notebookURI: String) { self.notebookURI = notebookURI }
}

public struct InterruptCommand: Codable, Sendable, Equatable {
  public let notebookURI: String
  public let kernelSessionID: String?
  public let runID: String?
  enum CodingKeys: String, CodingKey {
    case notebookURI = "notebookUri"
    case kernelSessionID = "kernelSessionId"
    case runID = "runId"
  }
  public init(notebookURI: String, kernelSessionID: String? = nil, runID: String? = nil) {
    self.notebookURI = notebookURI
    self.kernelSessionID = kernelSessionID
    self.runID = runID
  }
}

public struct RestartSessionCommand: Codable, Sendable, Equatable {
  public let notebookURI: String
  public let executable: String
  public let workingDirectory: String
  public let createIfMissing: Bool
  enum CodingKeys: String, CodingKey {
    case notebookURI = "notebookUri"
    case executable, workingDirectory, createIfMissing
  }
  public init(
    notebookURI: String, executable: String, workingDirectory: String, createIfMissing: Bool = false
  ) {
    self.notebookURI = notebookURI
    self.executable = executable
    self.workingDirectory = workingDirectory
    self.createIfMissing = createIfMissing
  }
}

public struct MoveSessionCommand: Codable, Sendable, Equatable {
  public let notebookURI: String
  public let newNotebookURI: String
  enum CodingKeys: String, CodingKey {
    case notebookURI = "notebookUri"
    case newNotebookURI = "newNotebookUri"
  }
  public init(notebookURI: String, newNotebookURI: String) {
    self.notebookURI = notebookURI
    self.newNotebookURI = newNotebookURI
  }
}

public struct ExportHTMLCommand: Codable, Sendable, Equatable {
  public let notebookURI: String
  public let download: Bool
  public let files: [String]
  public let includeCode: Bool
  public let assetURL: String?
  enum CodingKeys: String, CodingKey {
    case notebookURI = "notebookUri"
    case download, files, includeCode
    case assetURL = "assetUrl"
  }
  public init(
    notebookURI: String, download: Bool, files: [String], includeCode: Bool, assetURL: String? = nil
  ) {
    self.notebookURI = notebookURI
    self.download = download
    self.files = files
    self.includeCode = includeCode
    self.assetURL = assetURL
  }
}

public enum DisplayTheme: String, Codable, Sendable, Equatable { case light, dark }

public enum PackageSource: Codable, Sendable, Equatable {
  case venv(executable: String)

  enum CodingKeys: String, CodingKey { case kind, executable }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(String.self, forKey: .kind) {
    case "venv": self = .venv(executable: try container.decode(String.self, forKey: .executable))
    case let kind:
      throw DecodingError.dataCorruptedError(
        forKey: .kind, in: container, debugDescription: "Unknown package source: \(kind)")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .venv(let executable):
      try container.encode("venv", forKey: .kind)
      try container.encode(executable, forKey: .executable)
    }
  }
}

public enum MarimoCommand: Codable, Sendable, Equatable {
  case execute(ExecuteCommand)
  case updateUIElement(UpdateUIElementCommand)
  case interrupt(InterruptCommand)
  case deleteCell(SessionCellCommand)
  case sendStdin(SendStdinCommand)
  case closeSession(NotebookURICommand)
  case restartSession(RestartSessionCommand)
  case moveSession(MoveSessionCommand)
  case listSessions
  case shutdownAllSessions
  case listPackages(notebookURI: String, source: PackageSource)
  case printNotebook(OwnedNotebookDocumentV1)
  case parseNotebook(source: String)
  case readNotebookOutputs(notebookURI: String, sessionCachePath: String?)
  case setDisplayTheme(DisplayTheme)
  case exportHTML(ExportHTMLCommand)
  case exportIPYNB(NotebookURICommand)
  case exportMarkdown(NotebookURICommand)

  enum CodingKeys: String, CodingKey {
    case kind
    case notebookURI = "notebookUri"
    case executable
    case workingDirectory
    case cells
    case kernelSessionID = "kernelSessionId"
    case objectIDs = "objectIds"
    case values
    case request
    case token
    case cellID = "cellId"
    case text
    case runID = "runId"
    case createIfMissing
    case newNotebookURI = "newNotebookUri"
    case document
    case source
    case sessionCachePath
    case theme
    case download
    case files
    case includeCode
    case assetURL = "assetUrl"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(String.self, forKey: .kind)
    switch kind {
    case "execute": self = .execute(try ExecuteCommand(from: decoder))
    case "update-ui-element": self = .updateUIElement(try UpdateUIElementCommand(from: decoder))
    case "interrupt": self = .interrupt(try InterruptCommand(from: decoder))
    case "delete-cell": self = .deleteCell(try SessionCellCommand(from: decoder))
    case "send-stdin": self = .sendStdin(try SendStdinCommand(from: decoder))
    case "close-session": self = .closeSession(try NotebookURICommand(from: decoder))
    case "restart-session": self = .restartSession(try RestartSessionCommand(from: decoder))
    case "move-session": self = .moveSession(try MoveSessionCommand(from: decoder))
    case "list-sessions": self = .listSessions
    case "shutdown-all-sessions": self = .shutdownAllSessions
    case "list-packages":
      self = .listPackages(
        notebookURI: try container.decode(String.self, forKey: .notebookURI),
        source: try container.decode(PackageSource.self, forKey: .source)
      )
    case "print-notebook":
      self = .printNotebook(try container.decode(OwnedNotebookDocumentV1.self, forKey: .document))
    case "parse-notebook":
      self = .parseNotebook(source: try container.decode(String.self, forKey: .source))
    case "read-notebook-outputs":
      self = .readNotebookOutputs(
        notebookURI: try container.decode(String.self, forKey: .notebookURI),
        sessionCachePath: try container.decodeIfPresent(String.self, forKey: .sessionCachePath))
    case "set-display-theme":
      self = .setDisplayTheme(try container.decode(DisplayTheme.self, forKey: .theme))
    case "export-html": self = .exportHTML(try ExportHTMLCommand(from: decoder))
    case "export-ipynb": self = .exportIPYNB(try NotebookURICommand(from: decoder))
    case "export-markdown": self = .exportMarkdown(try NotebookURICommand(from: decoder))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .kind, in: container, debugDescription: "Unknown command: \(kind)")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .execute(let value):
      try container.encode("execute", forKey: .kind)
      try container.encode(value.notebookURI, forKey: .notebookURI)
      try container.encode(value.executable, forKey: .executable)
      try container.encode(value.workingDirectory, forKey: .workingDirectory)
      try container.encode(value.cells, forKey: .cells)
    case .updateUIElement(let value):
      try container.encode("update-ui-element", forKey: .kind)
      try container.encode(value.notebookURI, forKey: .notebookURI)
      try container.encode(value.kernelSessionID, forKey: .kernelSessionID)
      try container.encode(value.objectIDs, forKey: .objectIDs)
      try container.encode(value.values, forKey: .values)
      try container.encodeIfPresent(value.request, forKey: .request)
      try container.encodeIfPresent(value.token, forKey: .token)
    case .interrupt(let value):
      try container.encode("interrupt", forKey: .kind)
      try container.encode(value.notebookURI, forKey: .notebookURI)
      try container.encodeIfPresent(value.kernelSessionID, forKey: .kernelSessionID)
      try container.encodeIfPresent(value.runID, forKey: .runID)
    case .deleteCell(let value):
      try container.encode("delete-cell", forKey: .kind)
      try container.encode(value.notebookURI, forKey: .notebookURI)
      try container.encode(value.kernelSessionID, forKey: .kernelSessionID)
      try container.encode(value.cellID, forKey: .cellID)
    case .sendStdin(let value):
      try container.encode("send-stdin", forKey: .kind)
      try container.encode(value.notebookURI, forKey: .notebookURI)
      try container.encode(value.kernelSessionID, forKey: .kernelSessionID)
      try container.encode(value.text, forKey: .text)
    case .closeSession(let value):
      try container.encode("close-session", forKey: .kind)
      try container.encode(value.notebookURI, forKey: .notebookURI)
    case .restartSession(let value):
      try container.encode("restart-session", forKey: .kind)
      try container.encode(value.notebookURI, forKey: .notebookURI)
      try container.encode(value.executable, forKey: .executable)
      try container.encode(value.workingDirectory, forKey: .workingDirectory)
      try container.encode(value.createIfMissing, forKey: .createIfMissing)
    case .moveSession(let value):
      try container.encode("move-session", forKey: .kind)
      try container.encode(value.notebookURI, forKey: .notebookURI)
      try container.encode(value.newNotebookURI, forKey: .newNotebookURI)
    case .listSessions: try container.encode("list-sessions", forKey: .kind)
    case .shutdownAllSessions: try container.encode("shutdown-all-sessions", forKey: .kind)
    case .listPackages(let notebookURI, let source):
      try container.encode("list-packages", forKey: .kind)
      try container.encode(notebookURI, forKey: .notebookURI)
      try container.encode(source, forKey: .source)
    case .printNotebook(let document):
      try container.encode("print-notebook", forKey: .kind)
      try container.encode(document, forKey: .document)
    case .parseNotebook(let source):
      try container.encode("parse-notebook", forKey: .kind)
      try container.encode(source, forKey: .source)
    case .readNotebookOutputs(let uri, let path):
      try container.encode("read-notebook-outputs", forKey: .kind)
      try container.encode(uri, forKey: .notebookURI)
      try container.encodeIfPresent(path, forKey: .sessionCachePath)
    case .setDisplayTheme(let theme):
      try container.encode("set-display-theme", forKey: .kind)
      try container.encode(theme, forKey: .theme)
    case .exportHTML(let value):
      try container.encode("export-html", forKey: .kind)
      try container.encode(value.notebookURI, forKey: .notebookURI)
      try container.encode(value.download, forKey: .download)
      try container.encode(value.files, forKey: .files)
      try container.encode(value.includeCode, forKey: .includeCode)
      try container.encodeIfPresent(value.assetURL, forKey: .assetURL)
    case .exportIPYNB(let value):
      try container.encode("export-ipynb", forKey: .kind)
      try container.encode(value.notebookURI, forKey: .notebookURI)
    case .exportMarkdown(let value):
      try container.encode("export-markdown", forKey: .kind)
      try container.encode(value.notebookURI, forKey: .notebookURI)
    }
  }
}
