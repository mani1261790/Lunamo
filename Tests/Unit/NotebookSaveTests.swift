import Foundation
import MarimoApplication
import MarimoBackend
import MarimoDomain
import Testing

private enum SaveEvent: Sendable, Equatable {
  case printed(OwnedNotebookDocumentV1)
  case opened(String)
  case saved(String)
  case closed(String)
  case moved(String, String)
  case sessionClosed(String)
}

private enum SaveBackendError: Error { case expected }

private actor SaveRecordingBackend: MarimoBackend {
  private let source: String
  private let failDidSave: Bool
  private let failMove: Bool
  private let failDidClose: Bool
  private var ready = false
  private var recorded: [SaveEvent] = []

  init(
    source: String,
    failDidSave: Bool = false,
    failMove: Bool = false,
    failDidClose: Bool = false
  ) {
    self.source = source
    self.failDidSave = failDidSave
    self.failMove = failMove
    self.failDidClose = failDidClose
  }

  func status() -> BackendStatus { ready ? .ready : .unavailable }
  func start() { ready = true }
  func parseNotebook(source _: String) -> NotebookParseOutcome { .convertible }
  func printNotebook(_ document: OwnedNotebookDocumentV1) throws -> String {
    recorded.append(.printed(document))
    return source
  }
  func didOpenNotebook(_ snapshot: NotebookSyncSnapshot) {
    recorded.append(.opened(snapshot.uri))
  }
  func didSaveNotebook(uri: String) throws {
    if failDidSave { throw SaveBackendError.expected }
    recorded.append(.saved(uri))
  }
  func didCloseNotebook(uri: String, cellURIs _: [String]) throws {
    recorded.append(.closed(uri))
    if failDidClose { throw SaveBackendError.expected }
  }
  func moveSession(notebookURI: String, newNotebookURI: String) throws {
    recorded.append(.moved(notebookURI, newNotebookURI))
    if failMove { throw SaveBackendError.expected }
  }
  func closeSession(notebookURI: String) {
    recorded.append(.sessionClosed(notebookURI))
  }
  func shutdown() { ready = false }
  func events() -> [SaveEvent] { recorded }
  func resetEvents() { recorded = [] }
}

@Suite("Notebook save lifecycle", .serialized)
@MainActor
struct NotebookSaveTests {
  @Test("A new notebook has one empty cell and no synthesized Python source")
  func newNotebookShape() {
    let document = NotebookDocumentState()
    #expect(document.sourceURL == nil)
    #expect(document.owned.header == "")
    #expect(document.owned.metadata.isEmpty)
    #expect(document.cells.count == 1)
    #expect(document.cells[0].code.isEmpty)
  }

  @Test("Command-S on a clean opened document skips print and disk write")
  func cleanSaveIsNoOp() async throws {
    try await withTemporaryDirectory { directory in
      let target = directory.appending(path: "clean.py")
      try Data("original\n".utf8).write(to: target)
      let identity = try await AtomicFileWriter().identity(at: target)
      let backend = SaveRecordingBackend(source: "unexpected\n")
      let store = NotebookStore(
        backend: backend,
        document: NotebookDocumentState(
          sourceURL: target,
          dirty: false,
          lastSavedFileIdentity: identity
        )
      )

      #expect(try await store.save() == .unchanged)
      #expect(await backend.events().isEmpty)
      #expect(try String(contentsOf: target, encoding: .utf8) == "original\n")
    }
  }

  @Test("Save writes print-notebook bytes and clears dirty only after didSave")
  func successfulSave() async throws {
    try await withTemporaryDirectory { directory in
      let target = directory.appending(path: "saved.py")
      try Data("original\n".utf8).write(to: target)
      let identity = try await AtomicFileWriter().identity(at: target)
      let printed = "# exact\r\nvalue = 42  "
      let backend = SaveRecordingBackend(source: printed)
      let document = NotebookDocumentState(
        sourceURL: target,
        cells: [NotebookCellState(code: "value = 42")],
        dirty: true,
        lastSavedFileIdentity: identity
      )
      let store = NotebookStore(backend: backend, document: document)

      #expect(try await store.save() == .saved(target))
      #expect(try String(contentsOf: target, encoding: .utf8) == printed)
      #expect(!store.document.dirty)
      let events = await backend.events()
      #expect(events.count == 2)
      guard case .printed(let owned) = events[0] else {
        Issue.record("print-notebook was not first")
        return
      }
      #expect(owned.cells[0].code == "value = 42")
      #expect(events[1] == .saved(document.notebookURI))
    }
  }

  @Test("didSave failure leaves the document dirty")
  func didSaveFailureKeepsDirty() async throws {
    try await withTemporaryDirectory { directory in
      let target = directory.appending(path: "failure.py")
      try Data("original\n".utf8).write(to: target)
      let identity = try await AtomicFileWriter().identity(at: target)
      let backend = SaveRecordingBackend(source: "written\n", failDidSave: true)
      let store = NotebookStore(
        backend: backend,
        document: NotebookDocumentState(
          sourceURL: target,
          dirty: true,
          lastSavedFileIdentity: identity
        )
      )

      await #expect(throws: SaveBackendError.expected) { try await store.save() }
      #expect(store.document.dirty)
      #expect(try String(contentsOf: target, encoding: .utf8) == "written\n")
    }
  }

  @Test("An external disk edit blocks normal Save and keeps both versions")
  func externalEditConflict() async throws {
    try await withTemporaryDirectory { directory in
      let target = directory.appending(path: "conflict.py")
      try Data("original\n".utf8).write(to: target)
      let identity = try await AtomicFileWriter().identity(at: target)
      let backend = SaveRecordingBackend(source: "local edit\n")
      let store = NotebookStore(
        backend: backend,
        document: NotebookDocumentState(
          sourceURL: target,
          dirty: true,
          lastSavedFileIdentity: identity
        )
      )
      try Data("external edit\n".utf8).write(to: target)

      await #expect(throws: AtomicWriteError.conflict(target)) { try await store.save() }
      #expect(store.document.dirty)
      #expect(store.saveConflictURL == target)
      #expect(try String(contentsOf: target, encoding: .utf8) == "external edit\n")
      let localCopy = directory.appending(path: "local-copy.py")
      #expect(try await store.saveAs(to: localCopy) == .saved(localCopy))
      #expect(try String(contentsOf: localCopy, encoding: .utf8) == "local edit\n")
      #expect(try String(contentsOf: target, encoding: .utf8) == "external edit\n")
    }
  }

  @Test("Save As moves a live session before LSP reattachment")
  func saveAsMovesSession() async throws {
    try await withTemporaryDirectory { directory in
      let oldURL = directory.appending(path: "old.py")
      let newURL = directory.appending(path: "new.py")
      try Data("old source\n".utf8).write(to: oldURL)
      let identity = try await AtomicFileWriter().identity(at: oldURL)
      var cell = NotebookCellState(code: "value = 2")
      cell.runtime = CellRuntimeState(output: .string("kept"))
      let document = NotebookDocumentState(
        sourceURL: oldURL,
        cells: [cell],
        dirty: true,
        lastSavedFileIdentity: identity,
        kernelSessionID: "session-1"
      )
      let backend = SaveRecordingBackend(source: "new source\n")
      let store = NotebookStore(backend: backend, document: document)
      await store.startBackend()
      await backend.resetEvents()

      #expect(try await store.saveAs(to: newURL) == .saved(newURL))
      #expect(try String(contentsOf: oldURL, encoding: .utf8) == "old source\n")
      #expect(try String(contentsOf: newURL, encoding: .utf8) == "new source\n")
      #expect(store.document.sourceURL == newURL)
      #expect(store.document.kernelSessionID == "session-1")
      #expect(store.document.cells[0].runtime.output == .string("kept"))
      let oldURI = document.notebookURI
      let newURI = store.document.notebookURI
      #expect(
        await backend.events() == [
          .printed(document.persistentDocumentForSaving()),
          .moved(oldURI, newURI),
          .closed(oldURI),
          .opened(newURI),
          .saved(newURI),
        ]
      )
    }
  }

  @Test("Save As to the current URL follows normal Save semantics")
  func saveAsSameURLUsesSave() async throws {
    try await withTemporaryDirectory { directory in
      let target = directory.appending(path: "same.py")
      try Data("old\n".utf8).write(to: target)
      let identity = try await AtomicFileWriter().identity(at: target)
      let backend = SaveRecordingBackend(source: "new\n")
      let store = NotebookStore(
        backend: backend,
        document: NotebookDocumentState(
          sourceURL: target,
          dirty: true,
          lastSavedFileIdentity: identity
        )
      )

      #expect(try await store.saveAs(to: target) == .saved(target))
      #expect(try String(contentsOf: target, encoding: .utf8) == "new\n")
      #expect(await backend.events().count == 2)
    }
  }

  @Test("Save As keeps the new file and resets runtime when move-session fails")
  func saveAsMoveFailureFallsBack() async throws {
    try await withTemporaryDirectory { directory in
      let oldURL = directory.appending(path: "old.py")
      let newURL = directory.appending(path: "new.py")
      try Data("old source\n".utf8).write(to: oldURL)
      let identity = try await AtomicFileWriter().identity(at: oldURL)
      var cell = NotebookCellState(code: "value = 2")
      cell.runtime = CellRuntimeState(output: .string("must clear"), widgetIDs: [UUID()])
      let document = NotebookDocumentState(
        sourceURL: oldURL,
        cells: [cell],
        dirty: true,
        lastSavedFileIdentity: identity,
        kernelSessionID: "session-1"
      )
      let backend = SaveRecordingBackend(source: "new source\n", failMove: true)
      let store = NotebookStore(backend: backend, document: document)
      await store.startBackend()
      await backend.resetEvents()

      #expect(try await store.saveAs(to: newURL) == .savedWithSessionReset(newURL))
      #expect(try String(contentsOf: oldURL, encoding: .utf8) == "old source\n")
      #expect(try String(contentsOf: newURL, encoding: .utf8) == "new source\n")
      #expect(store.document.sourceURL == newURL)
      #expect(store.document.kernelSessionID == nil)
      #expect(store.document.cells[0].runtime == CellRuntimeState())
      #expect(store.saveMessage != nil)
    }
  }

  @Test("Save As still adopts the new file when move and didClose both fail")
  func saveAsMoveAndCloseFailureFallsBack() async throws {
    try await withTemporaryDirectory { directory in
      let oldURL = directory.appending(path: "old.py")
      let newURL = directory.appending(path: "new.py")
      try Data("old source\n".utf8).write(to: oldURL)
      let identity = try await AtomicFileWriter().identity(at: oldURL)
      let document = NotebookDocumentState(
        sourceURL: oldURL,
        cells: [NotebookCellState(code: "value = 2")],
        dirty: true,
        lastSavedFileIdentity: identity,
        kernelSessionID: "session-1"
      )
      let backend = SaveRecordingBackend(
        source: "new source\n",
        failMove: true,
        failDidClose: true
      )
      let store = NotebookStore(backend: backend, document: document)
      await store.startBackend()
      await backend.resetEvents()

      #expect(try await store.saveAs(to: newURL) == .savedWithSessionReset(newURL))
      #expect(store.document.sourceURL == newURL)
      #expect(store.document.kernelSessionID == nil)
      #expect(!store.document.dirty)
      #expect(try String(contentsOf: newURL, encoding: .utf8) == "new source\n")
    }
  }

  @Test("Close sends didClose before closing a live session")
  func closeOrdering() async throws {
    let document = NotebookDocumentState(kernelSessionID: "session-1")
    let backend = SaveRecordingBackend(source: "")
    let store = NotebookStore(backend: backend, document: document)
    await store.startBackend()
    await backend.resetEvents()

    await store.close()

    #expect(
      await backend.events() == [
        .closed(document.notebookURI),
        .sessionClosed(document.notebookURI),
      ]
    )
  }

  private func withTemporaryDirectory(
    _ operation: (URL) async throws -> Void
  ) async throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "marimonative-save-lifecycle-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await operation(directory)
  }
}
