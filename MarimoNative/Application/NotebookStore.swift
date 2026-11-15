import Combine
import Foundation
import MarimoBackend
import MarimoDomain
import MarimoEnvironment
import MarimoWidgets

@MainActor
public final class NotebookStore: ObservableObject {
  @Published public internal(set) var document: NotebookDocumentState
  @Published public internal(set) var backendStatus: BackendStatus = .unavailable
  @Published public internal(set) var openState: OpenState = .idle
  @Published public internal(set) var synchronizationError: String?
  @Published public internal(set) var focusedCellID: UUID?
  @Published public var assistantPresented = false
  @Published public internal(set) var codeSelections: [UUID: String] = [:]
  @Published public internal(set) var saveConflictURL: URL?
  @Published public internal(set) var saveMessage: String?
  @Published public internal(set) var environmentCandidates: [PythonEnvironmentCandidate] = []
  @Published public internal(set) var environmentAvailability:
    [String: PythonEnvironmentAvailability] = [:]
  @Published public internal(set) var environmentsSearching = false
  @Published public internal(set) var environmentState: NotebookEnvironmentState = .notConfigured
  @Published public internal(set) var executionTrustPromptPresented = false
  @Published public internal(set) var executionFolderTrusted = false
  @Published public internal(set) var sessionState: NotebookSessionState = .notStarted
  @Published public internal(set) var forceRestartAvailable = false
  @Published public internal(set) var backendRecoveryStopped = false
  @Published public internal(set) var backendLogs: [String] = []
  @Published public var backendLogsPresented = false
  @Published public internal(set) var sidebarFiles: [NotebookSidebarFile] = []
  @Published public internal(set) var variables: [NotebookVariableState] = []
  @Published public internal(set) var externalFileState: ExternalFileState = .none
  @Published public internal(set) var conflictBannerDismissed = false
  @Published public internal(set) var recentDocuments: [URL] = []
  @Published public internal(set) var userFacingError: NotebookUserFacingError?
  @Published public var recoverySourcePresented = false
  @Published public internal(set) var installedPackages: [NotebookPackage] = []
  @Published public internal(set) var packagesLoading = false
  @Published public internal(set) var packagesLoaded = false
  @Published public internal(set) var packagesError: String?
  @Published public internal(set) var missingPackages: [String] = []
  var runtimePackageAlertSessionID: String?
  @Published public internal(set) var packageOperationState: NotebookPackageOperationState = .idle
  @Published public internal(set) var packageEnvironmentScope: ManagedPythonEnvironmentScope =
    .shared
  @Published public internal(set) var managedEnvironmentSummaries:
    [ManagedPythonEnvironmentSummary] = []
  @Published public internal(set) var managedPackageCacheSize: Int64 = 0
  @Published public internal(set) var environmentStorageMessage: String?

  public let widgetValueStore: WidgetValueStore

  let backend: any MarimoBackend
  let documentService: DocumentService
  let fileWriter: AtomicFileWriter
  let recentDocumentStore: RecentDocumentStore
  let environmentDiscovery: PythonEnvironmentDiscovery
  let environmentPreflight: PythonPreflightService
  let packageManager: (any NotebookPackageManaging)?
  let managedEnvironmentStore: ManagedPythonEnvironmentStore
  let folderTrustStore: FolderTrustStore
  public let applicationWorkspaceDirectory: URL
  var synchronizedURI: String?
  var synchronizedCellURIs: [String] = []
  var filePresenter: NotebookFilePresenter?
  var ignoreExternalChangesUntilNextSave = false
  var runOnceAuthorized = false
  var pendingRunRequest: PendingRunRequest?
  var backendEventTask: Task<Void, Never>?
  var sessionResolutionTask: Task<Void, Never>?
  var completionRefreshTask: Task<Void, Never>?
  var pendingTextSynchronizations: [UUID: Task<Void, Error>] = [:]
  var markdownRevisions: [UUID: UUID] = [:]
  var retiredKernelSessionIDs: Set<String> = []
  var runAwaitingCompletion = false
  let sessionResolutionTimeout: Duration
  var interruptTimeoutTask: Task<Void, Never>?
  let interruptTimeout: Duration

  public init(
    backend: any MarimoBackend,
    document: NotebookDocumentState = NotebookDocumentState(),
    documentService: DocumentService = DocumentService(),
    fileWriter: AtomicFileWriter = AtomicFileWriter(),
    environmentDiscovery: PythonEnvironmentDiscovery = PythonEnvironmentDiscovery(),
    environmentPreflight: PythonPreflightService = PythonPreflightService(),
    packageManager: (any NotebookPackageManaging)? = nil,
    managedEnvironmentStore: ManagedPythonEnvironmentStore = ManagedPythonEnvironmentStore(),
    folderTrustStore: FolderTrustStore = FolderTrustStore(),
    recentDocumentStore: RecentDocumentStore = RecentDocumentStore(),
    widgetValueStore: WidgetValueStore = WidgetValueStore(),
    applicationWorkspaceDirectory: URL = ApplicationWorkspaceDirectory.resolve(),
    sessionResolutionTimeout: Duration = .seconds(15),
    interruptTimeout: Duration = .seconds(10)
  ) {
    self.backend = backend
    self.document = document
    self.documentService = documentService
    self.fileWriter = fileWriter
    self.environmentDiscovery = environmentDiscovery
    self.environmentPreflight = environmentPreflight
    self.packageManager = packageManager
    self.managedEnvironmentStore = managedEnvironmentStore
    self.folderTrustStore = folderTrustStore
    self.recentDocumentStore = recentDocumentStore
    self.widgetValueStore = widgetValueStore
    self.applicationWorkspaceDirectory = applicationWorkspaceDirectory.standardizedFileURL
    self.sessionResolutionTimeout = sessionResolutionTimeout
    self.interruptTimeout = interruptTimeout
  }

  public func send(_ intent: NotebookIntent) async {
    do {
      try await perform(intent)
      synchronizationError = nil
    } catch {
      synchronizationError = String(describing: error)
    }
  }

  private func perform(_ intent: NotebookIntent) async throws {
    switch intent {
    case .addCell:
      try await insertCell(after: document.cells.last?.runtimeID)
    case .insertCell(let after):
      try await insertCell(after: after)
    case .insertCellAt(let position):
      try await insertCell(at: position)
    case .insertTextCellAt(let position):
      let documentID = document.documentID
      let projection = try await backend.textCell(source: "", markdown: "")
      guard document.documentID == documentID else { return }
      var cell = NotebookCellState(code: projection.source)
      cell.editor.markdown = projection.markdown
      try await insertCell(at: position, cell: cell)
    case .updateMarkdown(let cellID, let markdown):
      try await updateMarkdown(cellID: cellID, markdown: markdown)
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
      if document.kernelSessionID != sessionID { widgetValueStore.clear() }
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

    if document.cells[index].runtime.status == .error
      || document.cells[index].runtime.status == .disabledTransitively
    {
      document.cells[index].runtime.status = .idle
      document.cells[index].runtime.stale = document.cells[index].runtime.lastExecutedCode != nil
    }

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
    try await insertCell(at: insertionIndex)
  }

  private func insertCell(at position: Int, cell: NotebookCellState = NotebookCellState())
    async throws
  {
    let insertionIndex = min(max(position, 0), document.cells.count)
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

  private func updateMarkdown(cellID: UUID, markdown: String) async throws {
    guard let index = cellIndex(cellID) else { return }
    let source = document.cells[index].code
    let documentID = document.documentID
    let revision = UUID()
    if let previous = markdownRevisions[cellID] {
      pendingTextSynchronizations.removeValue(forKey: previous)
    }
    markdownRevisions[cellID] = revision
    document.cells[index].editor.markdown = markdown
    document.recordPersistentChange()
    let task = Task<Void, Error> { @MainActor in
      let projection = try await self.backend.textCell(source: source, markdown: markdown)
      guard self.document.documentID == documentID,
        self.markdownRevisions[cellID] == revision, self.cellIndex(cellID) != nil
      else { return }
      guard projection.markdown != nil else { throw MarimoBackendCapabilityError.unavailable }
      try await self.updateCode(cellID: cellID, code: projection.source, hasMarkedText: false)
    }
    pendingTextSynchronizations[revision] = task
    do {
      try await task.value
      pendingTextSynchronizations.removeValue(forKey: revision)
    } catch {
      if markdownRevisions[cellID] != revision {
        pendingTextSynchronizations.removeValue(forKey: revision)
        return
      }
      // Keep a failed conversion in the flush barrier so Save/Run cannot use stale Python.
      throw error
    }
  }

  private func deleteCell(_ cellID: UUID) async throws {
    guard let index = cellIndex(cellID) else { return }
    if let revision = markdownRevisions.removeValue(forKey: cellID) {
      pendingTextSynchronizations.removeValue(forKey: revision)
    }
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
    try await flushCommittedTextChanges()
    guard let index = cellIndex(cellID) else { return }
    let original = document.cells[index]
    var duplicate = NotebookCellState(
      code: original.code,
      name: original.name,
      configuration: original.configuration,
      projectionMetadata: original.projectionMetadata
    )
    duplicate.editor.markdown = original.editor.markdown
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

  func closeSynchronizedDocument() async throws {
    guard let synchronizedURI else { return }
    try await backend.didCloseNotebook(uri: synchronizedURI, cellURIs: synchronizedCellURIs)
    self.synchronizedURI = nil
    synchronizedCellURIs = []
  }

}
