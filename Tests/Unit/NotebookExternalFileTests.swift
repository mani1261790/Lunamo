import Foundation
import MarimoBackend
import MarimoDomain
import Testing

@testable import MarimoApplication

private enum ExternalEvent: Sendable, Equatable {
  case parsed(String)
  case opened(String)
  case closed(String)
  case sessionClosed(String)
  case moved(String, String)
  case saved(String)
  case printed
}

private actor ExternalFileBackend: MarimoBackend {
  private var ready = false
  private var outcome: NotebookParseOutcome
  private var recorded: [ExternalEvent] = []
  private let printedSource: String

  init(outcome: NotebookParseOutcome, printedSource: String = "recreated") {
    self.outcome = outcome
    self.printedSource = printedSource
  }

  func status() -> BackendStatus { ready ? .ready : .unavailable }
  func start() { ready = true }
  func parseNotebook(source: String) -> NotebookParseOutcome {
    recorded.append(.parsed(source))
    return outcome
  }
  func printNotebook(_: OwnedNotebookDocumentV1) -> String {
    recorded.append(.printed)
    return printedSource
  }
  func didOpenNotebook(_ snapshot: NotebookSyncSnapshot) { recorded.append(.opened(snapshot.uri)) }
  func didCloseNotebook(uri: String, cellURIs _: [String]) { recorded.append(.closed(uri)) }
  func closeSession(notebookURI: String) { recorded.append(.sessionClosed(notebookURI)) }
  func moveSession(notebookURI: String, newNotebookURI: String) {
    recorded.append(.moved(notebookURI, newNotebookURI))
  }
  func didSaveNotebook(uri: String) { recorded.append(.saved(uri)) }
  func shutdown() { ready = false }
  func setOutcome(_ value: NotebookParseOutcome) { outcome = value }
  func events() -> [ExternalEvent] { recorded }
  func reset() { recorded = [] }
}

private actor PresentedEventRecorder {
  private var events: [NotebookPresentedFileEvent] = []

  func append(_ event: NotebookPresentedFileEvent) { events.append(event) }
  func containsDeletion(of url: URL) -> Bool { events.contains(.deleted(url)) }
}

@Suite("External file lifecycle", .serialized)
@MainActor
struct NotebookExternalFileTests {
  @Test("Self-save identity is ignored while external clean and dirty changes are surfaced")
  func selfSaveAndConflictClassification() async throws {
    try await withDirectory { directory in
      let target = directory.appending(path: "watched.py")
      try Data("one".utf8).write(to: target)
      let identity = try await AtomicFileWriter().identity(at: target)
      let store = makeStore(target: target, identity: identity)

      await store.handlePresentedFileEvent(.changed(target))
      #expect(store.externalFileState == .none)

      try Data("external".utf8).write(to: target)
      await store.handlePresentedFileEvent(.changed(target))
      #expect(store.externalFileState == .changed(target, localDirty: false))
      #expect(store.saveConflictURL == nil)
      await store.ignoreExternalChanges()
      #expect(store.externalFileState == .none)

      store.document.dirty = true
      store.ignoreExternalChangesUntilNextSave = false
      try Data("external again".utf8).write(to: target)
      await store.handlePresentedFileEvent(.changed(target))
      #expect(store.externalFileState == .changed(target, localDirty: true))
      #expect(store.saveConflictURL == target)
      await #expect(throws: AtomicWriteError.conflict(target)) { try await store.save() }
    }
  }

  @Test("Reload closes the old session and replaces state only after successful parse")
  func reloadOrderingAndRecovery() async throws {
    try await withDirectory { directory in
      let target = directory.appending(path: "reload.py")
      try Data("initial".utf8).write(to: target)
      let backend = ExternalFileBackend(outcome: .success(parsed(code: "initial")))
      let store = NotebookStore(
        backend: backend,
        recentDocumentStore: RecentDocumentStore(fileURL: directory.appending(path: "recent.json"))
      )
      await store.open(target)
      store.stopFileMonitoring()
      store.document.kernelSessionID = "live"
      store.document.cells[0].runtime = CellRuntimeState(output: textOutput("old"))
      await backend.reset()

      try Data("external valid".utf8).write(to: target)
      await backend.setOutcome(.success(parsed(code: "from disk")))
      store.presentExternalConflict(at: target)
      await store.reloadPresentedFile()

      #expect(store.document.cells[0].code == "from disk")
      #expect(store.document.cells[0].runtime.output == nil)
      #expect(store.sessionState == .notStarted)
      let events = await backend.events()
      #expect(events.first == .closed(target.resolvingSymlinksInPath().absoluteString))
      #expect(events.contains(.sessionClosed(target.resolvingSymlinksInPath().absoluteString)))
      #expect(events.last == .opened(target.resolvingSymlinksInPath().absoluteString))

      store.stopFileMonitoring()
      store.document.cells[0].code = "keep local editor"
      try Data("broken disk".utf8).write(to: target)
      await backend.setOutcome(.invalidSyntax(line: 2, column: 3))
      store.presentExternalConflict(at: target)
      await store.reloadPresentedFile()
      #expect(store.document.cells[0].code == "keep local editor")
      #expect(store.recoverySource == "broken disk")
      #expect(store.userFacingError?.code == .documentSyntax)
    }
  }

  @Test("Move updates the URL and live session while deletion preserves and recreates the buffer")
  func moveDeleteAndRecreate() async throws {
    try await withDirectory { directory in
      let oldURL = directory.appending(path: "old.py")
      let newURL = directory.appending(path: "new.py")
      try Data("source".utf8).write(to: oldURL)
      let backend = ExternalFileBackend(outcome: .success(parsed(code: "buffer")))
      let store = NotebookStore(
        backend: backend,
        recentDocumentStore: RecentDocumentStore(fileURL: directory.appending(path: "recent.json"))
      )
      await store.open(oldURL)
      store.stopFileMonitoring()
      store.document.kernelSessionID = "live"
      await backend.reset()

      try FileManager.default.moveItem(at: oldURL, to: newURL)
      await store.handlePresentedFileEvent(.moved(from: oldURL, to: newURL))
      #expect(store.document.sourceURL == newURL)
      #expect(store.document.cells[0].code == "buffer")
      #expect(
        await backend.events().contains(
          .moved(
            oldURL.resolvingSymlinksInPath().absoluteString,
            newURL.resolvingSymlinksInPath().absoluteString
          )))

      store.stopFileMonitoring()
      try FileManager.default.removeItem(at: newURL)
      await store.handlePresentedFileEvent(.deleted(newURL))
      #expect(store.isPresentedFileDeleted)
      #expect(store.document.cells[0].code == "buffer")
      await store.recreatePresentedFile()
      #expect(try String(contentsOf: newURL, encoding: .utf8) == "recreated")
      #expect(!store.document.dirty)
      #expect(store.externalFileState == .none)
      store.stopFileMonitoring()
    }
  }

  @Test("Recent documents remain bounded in the configured Application Support file")
  func recentDocumentsAreLocalAndBounded() async throws {
    try await withDirectory { directory in
      let recentFile = directory.appending(path: "Application Support/MarimoNative/recent.json")
      let recent = RecentDocumentStore(fileURL: recentFile)
      for index in 0..<(RecentDocumentStore.maximumCount + 3) {
        let url = directory.appending(path: "\(index).py")
        try Data().write(to: url)
        _ = try await recent.record(url)
      }
      let loaded = await recent.load()
      #expect(loaded.count == RecentDocumentStore.maximumCount)
      #expect(loaded.first?.lastPathComponent == "14.py")
      #expect(FileManager.default.fileExists(atPath: recentFile.path))
      #expect(
        RecentDocumentStore.defaultFileURL.path.contains("/Application Support/MarimoNative/"))
    }
  }

  @Test("File presenter and structured error taxonomy are explicit")
  func presenterAndErrorArchitecture() throws {
    let root = repositoryRoot()
    let presenter = try String(
      contentsOf: root.appending(path: "MarimoNative/Application/NotebookFilePresenter.swift"),
      encoding: .utf8
    )
    let errors = try String(
      contentsOf: root.appending(path: "MarimoNative/Application/ExternalFileState.swift"),
      encoding: .utf8
    )
    #expect(presenter.contains("NSFilePresenter"))
    #expect(presenter.contains("presentedItemDidMove"))
    #expect(presenter.contains("accommodatePresentedItemDeletion"))
    for code in [
      "MN-LSP-START-001", "MN-LSP-PROTOCOL-002", "MN-LSP-TIMEOUT-003",
      "MN-DOC-UTF8-101", "MN-DOC-SYNTAX-102", "MN-DOC-CONVERT-103",
      "MN-DOC-SAVE-104", "MN-DOC-CONFLICT-105", "MN-ENV-NOTFOUND-201",
      "MN-ENV-PREFLIGHT-202", "MN-ENV-MARIMO-203", "MN-KERNEL-START-301",
      "MN-KERNEL-CRASH-302", "MN-KERNEL-INTERRUPT-303", "MN-OUTPUT-DECODE-401",
      "MN-OUTPUT-SIZE-402", "MN-WIDGET-DECODE-501", "MN-WEB-CRASH-601",
    ] {
      #expect(errors.contains(code))
    }
  }

  @Test("File presenter reports an uncoordinated deletion")
  func presenterReportsDeletion() async throws {
    try await withDirectory { directory in
      let target = directory.appending(path: "deleted.py")
      try Data("source".utf8).write(to: target)
      let recorder = PresentedEventRecorder()
      let presenter = NotebookFilePresenter(url: target) { event in
        Task { await recorder.append(event) }
      }
      defer { presenter.stop() }

      try FileManager.default.removeItem(at: target)
      for _ in 0..<40 {
        if await recorder.containsDeletion(of: target) { return }
        try await Task.sleep(for: .milliseconds(25))
      }
      Issue.record("The presenter did not report the external deletion within one second")
    }
  }

  private func makeStore(target: URL, identity: FileIdentity) -> NotebookStore {
    NotebookStore(
      backend: ExternalFileBackend(outcome: .convertible),
      document: NotebookDocumentState(
        sourceURL: target,
        cells: [NotebookCellState(code: "local")],
        dirty: false,
        lastSavedFileIdentity: identity
      ),
      recentDocumentStore: RecentDocumentStore(
        fileURL: target.deletingLastPathComponent().appending(path: "recent.json"))
    )
  }

  private func parsed(code: String) -> ParsedNotebook {
    ParsedNotebook(cells: [
      ParsedNotebookCell(sourceID: "one", code: code, name: "_", configuration: CellConfiguration())
    ])
  }

  private func textOutput(_ value: String) -> MarimoOutput {
    MarimoOutput(channel: .output, mimeType: "text/plain", data: .string(value))
  }

  private func withDirectory(_ body: (URL) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await body(directory)
  }

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  }
}
