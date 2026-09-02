import Foundation

public struct FileIdentity: Sendable, Equatable {
  public var volumeIdentifier: String?
  public var fileIdentifier: String?
  public var modificationDate: Date
  public var size: UInt64
  public var contentSHA256: String

  public init(
    volumeIdentifier: String? = nil,
    fileIdentifier: String? = nil,
    modificationDate: Date,
    size: UInt64,
    contentSHA256: String
  ) {
    self.volumeIdentifier = volumeIdentifier
    self.fileIdentifier = fileIdentifier
    self.modificationDate = modificationDate
    self.size = size
    self.contentSHA256 = contentSHA256
  }
}

public struct NotebookDocumentState: Sendable, Equatable {
  public let documentID: UUID
  public var sourceURL: URL?
  public var owned: OwnedNotebookDocumentV1
  public var cells: [NotebookCellState]
  public var sourceRevision: UInt64
  public var notebookVersion: UInt64
  public var dirty: Bool
  public var lastSavedFileIdentity: FileIdentity?
  public var selectedCellID: UUID?
  public var projectionMetadata: [String: JSONValue]
  public var kernelSessionID: String?

  public init(
    documentID: UUID = UUID(),
    sourceURL: URL? = nil,
    owned: OwnedNotebookDocumentV1 = OwnedNotebookDocumentV1(
      cells: [OwnedNotebookCell(code: "", name: "_")],
      header: ""
    ),
    cells: [NotebookCellState]? = nil,
    sourceRevision: UInt64 = 0,
    notebookVersion: UInt64 = 1,
    dirty: Bool = false,
    lastSavedFileIdentity: FileIdentity? = nil,
    selectedCellID: UUID? = nil,
    projectionMetadata: [String: JSONValue] = [:],
    kernelSessionID: String? = nil
  ) {
    let openCells = cells ?? owned.cells.map(Self.openCell)
    self.documentID = documentID
    self.sourceURL = sourceURL
    self.owned = owned
    self.cells = openCells
    self.sourceRevision = sourceRevision
    self.notebookVersion = notebookVersion
    self.dirty = dirty
    self.lastSavedFileIdentity = lastSavedFileIdentity
    self.selectedCellID = selectedCellID ?? openCells.first?.runtimeID
    self.projectionMetadata = projectionMetadata
    self.kernelSessionID = kernelSessionID
  }

  public var notebookURI: String {
    if let sourceURL {
      return sourceURL.resolvingSymlinksInPath().standardizedFileURL.absoluteString
    }
    return "untitled:MarimoNative-\(documentID.uuidString)"
  }

  public func cellURI(_ cell: NotebookCellState) -> String {
    "marimo-native-notebook-cell://\(documentID.uuidString)/\(cell.runtimeID.uuidString)"
  }

  public func persistentDocumentForSaving() -> OwnedNotebookDocumentV1 {
    OwnedNotebookDocumentV1(
      metadata: owned.metadata,
      cells: cells.map { cell in
        OwnedNotebookCell(
          id: nil,
          code: cell.code,
          codeHash: nil,
          name: cell.name,
          config: OwnedNotebookCellConfig(
            column: cell.configuration.column,
            disabled: cell.configuration.disabled,
            hideCode: cell.configuration.hideCode
          )
        )
      },
      appOptions: owned.appOptions,
      header: owned.header
    )
  }

  public mutating func refreshOwnedCells() {
    owned.cells = cells.map { cell in
      OwnedNotebookCell(
        id: cell.sourceID,
        code: cell.code,
        codeHash: nil,
        name: cell.name,
        config: OwnedNotebookCellConfig(
          column: cell.configuration.column,
          disabled: cell.configuration.disabled,
          hideCode: cell.configuration.hideCode
        )
      )
    }
  }

  public mutating func recordPersistentChange() {
    sourceRevision += 1
    notebookVersion += 1
    dirty = true
    refreshOwnedCells()
  }

  private static func openCell(_ cell: OwnedNotebookCell) -> NotebookCellState {
    NotebookCellState(
      sourceID: cell.id,
      code: cell.code ?? "",
      name: normalizedName(cell.name),
      configuration: CellConfiguration(
        column: cell.config.column,
        disabled: cell.config.disabled ?? false,
        hideCode: cell.config.hideCode ?? false
      )
    )
  }

  private static func normalizedName(_ name: String?) -> String {
    guard let name, !name.isEmpty else { return "_" }
    return name
  }
}
