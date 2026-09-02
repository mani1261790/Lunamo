import MarimoDomain

public struct ManagedAppOptions: Codable, Sendable, Equatable {
  public var autoDownload: [String]

  public init(autoDownload: [String] = []) {
    self.autoDownload = autoDownload
  }
}

public struct AppOptions: Codable, Sendable, Equatable {
  public var managed: ManagedAppOptions
  public var passthrough: [String: JSONValue]

  public init(
    managed: ManagedAppOptions = ManagedAppOptions(),
    passthrough: [String: JSONValue] = [:]
  ) {
    self.managed = managed
    self.passthrough = passthrough
  }
}

public struct OwnedNotebookCellConfig: Codable, Sendable, Equatable {
  public var column: Int?
  public var disabled: Bool?
  public var hideCode: Bool?

  enum CodingKeys: String, CodingKey {
    case column
    case disabled
    case hideCode = "hide_code"
  }

  public init(column: Int? = nil, disabled: Bool? = nil, hideCode: Bool? = nil) {
    self.column = column
    self.disabled = disabled
    self.hideCode = hideCode
  }
}

public struct OwnedNotebookCell: Codable, Sendable, Equatable {
  public var id: String?
  public var code: String?
  public var codeHash: String?
  public var name: String?
  public var config: OwnedNotebookCellConfig

  enum CodingKeys: String, CodingKey {
    case id
    case code
    case codeHash = "code_hash"
    case name
    case config
  }

  public init(
    id: String? = nil,
    code: String? = nil,
    codeHash: String? = nil,
    name: String? = nil,
    config: OwnedNotebookCellConfig = OwnedNotebookCellConfig()
  ) {
    self.id = id
    self.code = code
    self.codeHash = codeHash
    self.name = name
    self.config = config
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    if let id {
      try container.encode(id, forKey: .id)
    } else {
      try container.encodeNil(forKey: .id)
    }
    if let code {
      try container.encode(code, forKey: .code)
    } else {
      try container.encodeNil(forKey: .code)
    }
    if let codeHash {
      try container.encode(codeHash, forKey: .codeHash)
    } else {
      try container.encodeNil(forKey: .codeHash)
    }
    if let name {
      try container.encode(name, forKey: .name)
    } else {
      try container.encodeNil(forKey: .name)
    }
    try container.encode(config, forKey: .config)
  }
}

public enum OwnedNotebookDocumentError: Error, Sendable, Equatable {
  case unsupportedVersion(String)
}

public struct OwnedNotebookDocumentV1: Codable, Sendable, Equatable {
  public let version: String
  public var metadata: [String: JSONValue]
  public var cells: [OwnedNotebookCell]
  public var appOptions: AppOptions
  public var header: String?

  enum CodingKeys: String, CodingKey {
    case version
    case metadata
    case cells
    case appOptions
    case header
  }

  public init(
    metadata: [String: JSONValue] = [:],
    cells: [OwnedNotebookCell] = [],
    appOptions: AppOptions = AppOptions(),
    header: String? = nil
  ) {
    self.version = "1"
    self.metadata = metadata
    self.cells = cells
    self.appOptions = appOptions
    self.header = header
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let version = try container.decode(String.self, forKey: .version)
    guard version == "1" else {
      throw OwnedNotebookDocumentError.unsupportedVersion(version)
    }
    self.version = version
    self.metadata = try container.decode([String: JSONValue].self, forKey: .metadata)
    self.cells = try container.decode([OwnedNotebookCell].self, forKey: .cells)
    self.appOptions =
      try container.decodeIfPresent(AppOptions.self, forKey: .appOptions) ?? AppOptions()
    self.header = try container.decodeIfPresent(String.self, forKey: .header)
  }
}

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
