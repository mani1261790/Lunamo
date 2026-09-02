import Combine
import Foundation
import MarimoBackend
import MarimoDomain

@MainActor
public final class NotebookStore: ObservableObject {
  public enum OpenState: Sendable, Equatable {
    case idle
    case loading(URL)
    case loaded(URL)
    case invalidSyntax(URL, line: Int?, column: Int?)
    case convertible(URL)
    case failed(URL, String)
  }

  @Published public private(set) var document: NotebookDocumentState
  @Published public private(set) var backendStatus: BackendStatus = .unavailable
  @Published public private(set) var openState: OpenState = .idle
  @Published public private(set) var synchronizationError: String?
  @Published public private(set) var focusedCellID: UUID?
  @Published public var inspectorPresented = true

  private let backend: any MarimoBackend
  private let documentService: DocumentService
  private var synchronizedURI: String?
  private var synchronizedCellURIs: [String] = []

  public init(
    backend: any MarimoBackend,
    document: NotebookDocumentState = NotebookDocumentState(),
    documentService: DocumentService = DocumentService()
  ) {
    self.backend = backend
    self.document = document
    self.documentService = documentService
  }

  public func send(_ intent: NotebookIntent) async {
    do {
      try await perform(intent)
      synchronizationError = nil
    } catch {
      synchronizationError = String(describing: error)
    }
  }

  public func refreshBackendStatus() async {
    backendStatus = await backend.status()
  }

  public func startBackend() async {
    do {
      try await backend.start()
      backendStatus = await backend.status()
      if backendStatus == .ready {
        try await synchronizeOpenDocument()
      }
    } catch {
      backendStatus = .unavailable
      synchronizationError = String(describing: error)
    }
  }

  public func open(_ url: URL) async {
    openState = .loading(url)
    do {
      let source = try await documentService.readSource(at: url)
      if backendStatus != .ready {
        try await backend.start()
        backendStatus = await backend.status()
      }
      switch try await backend.parseNotebook(source: source) {
      case .success(let parsed):
        try await closeSynchronizedDocument()
        document = NotebookDocumentState(sourceURL: url, owned: parsed.owned, dirty: false)
        focusedCellID = nil
        try await synchronizeOpenDocument()
        openState = .loaded(url)
      case .invalidSyntax(let line, let column):
        openState = .invalidSyntax(url, line: line, column: column)
      case .convertible:
        openState = .convertible(url)
      }
    } catch {
      openState = .failed(url, String(describing: error))
    }
  }

  public func shutdownBackend() async {
    try? await closeSynchronizedDocument()
    await backend.shutdown()
    backendStatus = .unavailable
  }

  public func recordSuccessfulSave(fileIdentity: FileIdentity? = nil) async {
    document.lastSavedFileIdentity = fileIdentity
    document.dirty = false
    guard synchronizedURI == document.notebookURI else { return }
    do {
      try await backend.didSaveNotebook(uri: document.notebookURI)
      synchronizationError = nil
    } catch {
      synchronizationError = String(describing: error)
    }
  }

  public func close() async {
    do {
      try await closeSynchronizedDocument()
      synchronizationError = nil
    } catch {
      synchronizationError = String(describing: error)
    }
  }

  public func focusEditor(_ cellID: UUID) {
    guard document.cells.contains(where: { $0.runtimeID == cellID }) else { return }
    document.selectedCellID = cellID
    focusedCellID = cellID
  }

  public func leaveEditor() {
    focusedCellID = nil
  }

  private func perform(_ intent: NotebookIntent) async throws {
    switch intent {
    case .addCell:
      try await insertCell(after: document.cells.last?.runtimeID)
    case .insertCell(let after):
      try await insertCell(after: after)
    case .deleteCell(let cellID):
      try await deleteCell(cellID)
    case .duplicateCell(let cellID):
      try await duplicateCell(cellID)
    case .moveCell(let cellID, let destination):
      try await moveCell(cellID, to: destination)
    case .selectCell(let cellID):
      guard document.cells.contains(where: { $0.runtimeID == cellID }) else { return }
      document.selectedCellID = cellID
    case .updateCode(let cellID, let code):
      try await updateCode(cellID: cellID, code: code, hasMarkedText: false)
    case .updateComposedCode(let cellID, let code, let hasMarkedText):
      try await updateCode(cellID: cellID, code: code, hasMarkedText: hasMarkedText)
    case .updateName(let cellID, let name):
      guard let index = cellIndex(cellID) else { return }
      let normalized = name.isEmpty ? "_" : name
      guard document.cells[index].name != normalized else { return }
      document.cells[index].name = normalized
      document.recordPersistentChange()
      try await sendCellData(document.cells[index])
    case .updateConfiguration(let cellID, let configuration):
      guard let index = cellIndex(cellID) else { return }
      guard document.cells[index].configuration != configuration else { return }
      document.cells[index].configuration = configuration
      document.recordPersistentChange()
      try await sendCellData(document.cells[index])
    case .updateMetadata(let metadata):
      guard document.owned.metadata != metadata else { return }
      document.owned.metadata = metadata
      document.recordPersistentChange()
      try await sendNotebookMetadata()
    case .updateAppOptions(let appOptions):
      guard document.owned.appOptions != appOptions else { return }
      document.owned.appOptions = appOptions
      document.recordPersistentChange()
      try await sendNotebookMetadata()
    case .updateHeader(let header):
      guard document.owned.header != header else { return }
      document.owned.header = header
      document.recordPersistentChange()
      try await sendNotebookMetadata()
    case .updateRuntime(let cellID, let runtime):
      guard let index = cellIndex(cellID) else { return }
      document.cells[index].runtime = runtime
    case .setKernelSessionID(let sessionID):
      document.kernelSessionID = sessionID
    case .runCell(let cellID, let executable, let workingDirectory):
      guard let index = cellIndex(cellID) else { return }
      guard !document.cells[index].editor.hasMarkedText else {
        throw NotebookStoreError.compositionActive(cellID)
      }
      let cell = document.cells[index]
      try await backend.execute(
        notebookURI: document.notebookURI,
        executable: executable,
        workingDirectory: workingDirectory,
        cells: [NotebookExecutionCell(runtimeID: cell.runtimeID, code: cell.code)]
      )
    }
  }

  private func updateCode(cellID: UUID, code: String, hasMarkedText: Bool) async throws {
    guard let index = cellIndex(cellID) else { return }
    let previous = document.cells[index].editor.lastSynchronizedCode
    document.cells[index].code = code
    document.cells[index].editor.hasMarkedText = hasMarkedText
    guard !hasMarkedText, previous != code else { return }

    document.cells[index].editor.textDocumentVersion += 1
    document.cells[index].editor.lastSynchronizedCode = code
    document.recordPersistentChange()
    let cell = document.cells[index]
    guard synchronizedURI == document.notebookURI else { return }
    let change = NotebookSynchronization.incrementalTextChange(
      cellURI: document.cellURI(cell),
      version: cell.editor.textDocumentVersion,
      previous: previous,
      current: code
    )
    try await backend.didChangeNotebook(
      uri: document.notebookURI,
      version: document.notebookVersion,
      change: .text(change)
    )
  }

  private func insertCell(after cellID: UUID?) async throws {
    let insertionIndex: Int
    if let cellID, let index = cellIndex(cellID) {
      insertionIndex = index + 1
    } else {
      insertionIndex = document.cells.count
    }
    let cell = NotebookCellState()
    document.cells.insert(cell, at: insertionIndex)
    document.selectedCellID = cell.runtimeID
    document.recordPersistentChange()
    guard synchronizedURI == document.notebookURI else { return }
    let projected = NotebookSynchronization.cell(document, cell)
    try await backend.didChangeNotebook(
      uri: document.notebookURI,
      version: document.notebookVersion,
      change: .structure(
        NotebookStructureChange(
          start: UInt64(insertionIndex),
          deleteCount: 0,
          cells: [projected],
          didOpen: [projected]
        )
      )
    )
    synchronizedCellURIs.insert(projected.uri, at: insertionIndex)
  }

  private func deleteCell(_ cellID: UUID) async throws {
    guard let index = cellIndex(cellID) else { return }
    let removed = document.cells[index]
    let removedURI = document.cellURI(removed)
    let sessionID = document.kernelSessionID
    document.cells.remove(at: index)
    document.selectedCellID =
      document.cells.indices.contains(index)
      ? document.cells[index].runtimeID : document.cells.last?.runtimeID
    document.recordPersistentChange()
    guard synchronizedURI == document.notebookURI else { return }
    try await backend.didChangeNotebook(
      uri: document.notebookURI,
      version: document.notebookVersion,
      change: .structure(
        NotebookStructureChange(
          start: UInt64(index),
          deleteCount: 1,
          cells: [],
          didClose: [removedURI]
        )
      )
    )
    if synchronizedCellURIs.indices.contains(index) {
      synchronizedCellURIs.remove(at: index)
    }
    if let sessionID {
      try await backend.deleteCell(
        notebookURI: document.notebookURI,
        kernelSessionID: sessionID,
        cellID: removed.runtimeID.uuidString
      )
    }
  }

  private func duplicateCell(_ cellID: UUID) async throws {
    guard let index = cellIndex(cellID) else { return }
    let original = document.cells[index]
    let duplicate = NotebookCellState(
      code: original.code,
      name: original.name,
      configuration: original.configuration,
      projectionMetadata: original.projectionMetadata
    )
    document.cells.insert(duplicate, at: index + 1)
    document.selectedCellID = duplicate.runtimeID
    document.recordPersistentChange()
    guard synchronizedURI == document.notebookURI else { return }
    let projected = NotebookSynchronization.cell(document, duplicate)
    try await backend.didChangeNotebook(
      uri: document.notebookURI,
      version: document.notebookVersion,
      change: .structure(
        NotebookStructureChange(
          start: UInt64(index + 1),
          deleteCount: 0,
          cells: [projected],
          didOpen: [projected]
        )
      )
    )
    synchronizedCellURIs.insert(projected.uri, at: index + 1)
  }

  private func moveCell(_ cellID: UUID, to destination: Int) async throws {
    guard let source = cellIndex(cellID), !document.cells.isEmpty else { return }
    let oldCount = document.cells.count
    let cell = document.cells.remove(at: source)
    let target = min(max(destination, 0), document.cells.count)
    document.cells.insert(cell, at: target)
    guard source != target else { return }
    document.recordPersistentChange()
    guard synchronizedURI == document.notebookURI else { return }
    let projected = document.cells.map { NotebookSynchronization.cell(document, $0) }
    try await backend.didChangeNotebook(
      uri: document.notebookURI,
      version: document.notebookVersion,
      change: .structure(
        NotebookStructureChange(
          start: 0,
          deleteCount: UInt64(oldCount),
          cells: projected
        )
      )
    )
    synchronizedCellURIs = projected.map(\.uri)
  }

  private func sendCellData(_ cell: NotebookCellState) async throws {
    guard synchronizedURI == document.notebookURI else { return }
    try await backend.didChangeNotebook(
      uri: document.notebookURI,
      version: document.notebookVersion,
      change: .cellData([NotebookSynchronization.cell(document, cell)])
    )
  }

  private func sendNotebookMetadata() async throws {
    guard synchronizedURI == document.notebookURI else { return }
    try await backend.didChangeNotebook(
      uri: document.notebookURI,
      version: document.notebookVersion,
      change: .notebookMetadata(NotebookSynchronization.notebookMetadata(document))
    )
  }

  private func synchronizeOpenDocument() async throws {
    guard backendStatus == .ready else { return }
    let snapshot = NotebookSynchronization.snapshot(document)
    try await backend.didOpenNotebook(snapshot)
    synchronizedURI = snapshot.uri
    synchronizedCellURIs = snapshot.cells.map(\.uri)
  }

  private func closeSynchronizedDocument() async throws {
    guard let synchronizedURI else { return }
    try await backend.didCloseNotebook(uri: synchronizedURI, cellURIs: synchronizedCellURIs)
    self.synchronizedURI = nil
    synchronizedCellURIs = []
  }

  private func cellIndex(_ cellID: UUID) -> Int? {
    document.cells.firstIndex { $0.runtimeID == cellID }
  }
}

public enum NotebookStoreError: Error, Sendable, Equatable {
  case compositionActive(UUID)
}
