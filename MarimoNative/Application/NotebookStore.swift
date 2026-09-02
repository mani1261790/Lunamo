import Combine
import Foundation
import MarimoBackend
import MarimoDomain
import MarimoEnvironment

@MainActor
public final class NotebookStore: ObservableObject {
  @Published public internal(set) var document: NotebookDocumentState
  @Published public internal(set) var backendStatus: BackendStatus = .unavailable
  @Published public private(set) var openState: OpenState = .idle
  @Published public internal(set) var synchronizationError: String?
  @Published public internal(set) var focusedCellID: UUID?
  @Published public var inspectorPresented = true
  @Published public internal(set) var saveConflictURL: URL?
  @Published public internal(set) var saveMessage: String?
  @Published public internal(set) var environmentCandidates: [PythonEnvironmentCandidate] = []
  @Published public internal(set) var environmentState: NotebookEnvironmentState = .notConfigured
  @Published public internal(set) var executionTrustPromptPresented = false
  @Published public internal(set) var executionFolderTrusted = false
  @Published public internal(set) var sessionState: NotebookSessionState = .notStarted

  let backend: any MarimoBackend
  private let documentService: DocumentService
  private let fileWriter: AtomicFileWriter
  let environmentDiscovery: PythonEnvironmentDiscovery
  let environmentPreflight: PythonPreflightService
  let folderTrustStore: FolderTrustStore
  private var synchronizedURI: String?
  private var synchronizedCellURIs: [String] = []
  var runOnceAuthorized = false
  var pendingRunRequest: PendingRunRequest?
  var backendEventTask: Task<Void, Never>?
  var sessionResolutionTask: Task<Void, Never>?
  var pendingTextSynchronizations: [UUID: Task<Void, Error>] = [:]
  var runAwaitingCompletion = false
  let sessionResolutionTimeout: Duration

  public init(
    backend: any MarimoBackend,
    document: NotebookDocumentState = NotebookDocumentState(),
    documentService: DocumentService = DocumentService(),
    fileWriter: AtomicFileWriter = AtomicFileWriter(),
    environmentDiscovery: PythonEnvironmentDiscovery = PythonEnvironmentDiscovery(),
    environmentPreflight: PythonPreflightService = PythonPreflightService(),
    folderTrustStore: FolderTrustStore = FolderTrustStore(),
    sessionResolutionTimeout: Duration = .seconds(15)
  ) {
    self.backend = backend
    self.document = document
    self.documentService = documentService
    self.fileWriter = fileWriter
    self.environmentDiscovery = environmentDiscovery
    self.environmentPreflight = environmentPreflight
    self.folderTrustStore = folderTrustStore
    self.sessionResolutionTimeout = sessionResolutionTimeout
  }

  public func send(_ intent: NotebookIntent) async {
    do {
      try await perform(intent)
      synchronizationError = nil
    } catch {
      synchronizationError = String(describing: error)
    }
  }

  public func open(_ url: URL) async {
    openState = .loading(url)
    do {
      let snapshot = try await documentService.readSnapshot(at: url)
      if backendStatus != .ready {
        try await backend.start()
        backendStatus = await backend.status()
      }
      switch try await backend.parseNotebook(source: snapshot.source) {
      case .success(let parsed):
        try await closeDocumentSynchronization()
        resetSessionState(to: .notStarted)
        document = NotebookDocumentState(
          sourceURL: url,
          owned: parsed.owned,
          dirty: false,
          lastSavedFileIdentity: snapshot.identity
        )
        focusedCellID = nil
        saveConflictURL = nil
        saveMessage = nil
        try await synchronizeOpenDocument()
        openState = .loaded(url)
        await discoverPythonEnvironments(for: url)
        await reattachSessionIfAvailable()
      case .invalidSyntax(let line, let column):
        openState = .invalidSyntax(url, line: line, column: column)
      case .convertible:
        openState = .convertible(url)
      }
    } catch {
      openState = .failed(url, String(describing: error))
    }
  }

  public func recordSuccessfulSave(fileIdentity: FileIdentity? = nil) async {
    if let fileIdentity { document.lastSavedFileIdentity = fileIdentity }
    guard synchronizedURI == document.notebookURI else { return }
    do {
      try await backend.didSaveNotebook(uri: document.notebookURI)
      document.dirty = false
      synchronizationError = nil
    } catch {
      synchronizationError = String(describing: error)
    }
  }

  public func save() async throws -> SaveOutcome {
    guard let target = document.sourceURL else { return .needsDestination }
    guard document.dirty else { return .unchanged }
    guard saveConflictURL == nil else { throw AtomicWriteError.conflict(target) }
    guard let expected = document.lastSavedFileIdentity else {
      saveConflictURL = target
      throw AtomicWriteError.conflict(target)
    }
    return try await saveCurrentDocument(to: target, expecting: .matching(expected))
  }

  public func saveAs(to target: URL) async throws -> SaveOutcome {
    let target = target.standardizedFileURL
    if document.sourceURL?.standardizedFileURL == target {
      return try await save()
    }
    return try await saveCurrentDocument(to: target, expecting: .unchecked, moving: true)
  }

  public func close() async {
    guard !document.dirty else {
      saveMessage = "Save changes before closing this notebook."
      return
    }
    await closeDiscardingChanges()
  }

  public func closeDiscardingChanges() async {
    do {
      try await closeDocumentSynchronization()
      document.dirty = false
      resetSessionState(to: .closed)
      synchronizationError = nil
    } catch {
      synchronizationError = String(describing: error)
    }
  }

  private func saveCurrentDocument(
    to target: URL,
    expecting expectation: AtomicWriteExpectation,
    moving: Bool = false
  ) async throws -> SaveOutcome {
    let source = try await backend.printNotebook(document.persistentDocumentForSaving())
    let identity: FileIdentity
    do {
      identity = try await fileWriter.write(source: source, to: target, expecting: expectation)
    } catch let error as AtomicWriteError {
      if case .conflict = error { saveConflictURL = document.sourceURL }
      throw error
    }

    if moving {
      return try await adoptSaveAs(target: target, identity: identity)
    }
    document.lastSavedFileIdentity = identity
    try await backend.didSaveNotebook(uri: document.notebookURI)
    document.dirty = false
    saveConflictURL = nil
    saveMessage = nil
    return .saved(target)
  }

  private func adoptSaveAs(target: URL, identity: FileIdentity) async throws -> SaveOutcome {
    let oldURI = document.notebookURI
    let newURI = target.resolvingSymlinksInPath().standardizedFileURL.absoluteString
    let hadLiveSession = document.kernelSessionID != nil
    var sessionMoveFailed = false

    if hadLiveSession {
      do {
        try await backend.moveSession(notebookURI: oldURI, newNotebookURI: newURI)
      } catch {
        sessionMoveFailed = true
      }
    }
    document.sourceURL = target
    document.lastSavedFileIdentity = identity
    if synchronizedURI == oldURI {
      if sessionMoveFailed {
        try? await backend.didCloseNotebook(uri: oldURI, cellURIs: synchronizedCellURIs)
      } else {
        try await backend.didCloseNotebook(uri: oldURI, cellURIs: synchronizedCellURIs)
      }
      synchronizedURI = nil
      synchronizedCellURIs = []
    }

    if sessionMoveFailed {
      try? await backend.closeSession(notebookURI: oldURI)
      document.kernelSessionID = nil
      for index in document.cells.indices {
        document.cells[index].runtime = CellRuntimeState()
      }
      saveMessage = "The file was saved, but the previous Python session could not be moved."
    } else {
      saveMessage = nil
    }
    try await synchronizeOpenDocument()
    try await backend.didSaveNotebook(uri: newURI)
    document.dirty = false
    saveConflictURL = nil
    return sessionMoveFailed ? .savedWithSessionReset(target) : .saved(target)
  }

  func closeDocumentSynchronization() async throws {
    let uri = synchronizedURI ?? document.notebookURI
    try await closeSynchronizedDocument()
    if document.kernelSessionID != nil {
      try await backend.closeSession(notebookURI: uri)
      document.kernelSessionID = nil
    }
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
      try await performRun(
        cellIDs: [cellID], executable: executable, workingDirectory: workingDirectory)
    case .runAll(let executable, let workingDirectory):
      try await performRun(
        cellIDs: document.cells.map(\.runtimeID),
        executable: executable,
        workingDirectory: workingDirectory
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
    let synchronizationID = UUID()
    let backend = self.backend
    let notebookURI = document.notebookURI
    let notebookVersion = document.notebookVersion
    let task = Task {
      try await backend.didChangeNotebook(
        uri: notebookURI,
        version: notebookVersion,
        change: .text(change)
      )
    }
    pendingTextSynchronizations[synchronizationID] = task
    defer { pendingTextSynchronizations.removeValue(forKey: synchronizationID) }
    try await task.value
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

  func synchronizeOpenDocument() async throws {
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
