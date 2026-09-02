import Foundation
import MarimoBackend
import MarimoDomain
import MarimoEnvironment
import Testing

@testable import MarimoApplication

private enum SyncEvent: Sendable, Equatable {
  case opened(NotebookSyncSnapshot)
  case changed(String, UInt64, NotebookSyncChange)
  case saved(String)
  case closed(String, [String])
  case deleted(String, String, String)
  case executed(String, [NotebookExecutionCell])
}

private actor SyncRecordingBackend: MarimoBackend {
  private var ready = false
  private var recorded: [SyncEvent] = []

  func status() -> BackendStatus { ready ? .ready : .unavailable }
  func start() { ready = true }
  func parseNotebook(source _: String) -> NotebookParseOutcome { .convertible }

  func didOpenNotebook(_ snapshot: NotebookSyncSnapshot) {
    recorded.append(.opened(snapshot))
  }

  func didChangeNotebook(uri: String, version: UInt64, change: NotebookSyncChange) {
    recorded.append(.changed(uri, version, change))
  }

  func didSaveNotebook(uri: String) {
    recorded.append(.saved(uri))
  }

  func didCloseNotebook(uri: String, cellURIs: [String]) {
    recorded.append(.closed(uri, cellURIs))
  }

  func deleteCell(notebookURI: String, kernelSessionID: String, cellID: String) {
    recorded.append(.deleted(notebookURI, kernelSessionID, cellID))
  }

  func execute(
    notebookURI: String,
    executable _: String,
    workingDirectory _: String,
    cells: [NotebookExecutionCell]
  ) {
    recorded.append(.executed(notebookURI, cells))
  }

  func shutdown() { ready = false }
  func events() -> [SyncEvent] { recorded }
}

@Suite("Notebook document synchronization", .serialized)
@MainActor
struct NotebookSynchronizationTests {
  @Test("Owned content and transient runtime state stay separate")
  func persistentAndTransientState() async {
    let owned = OwnedNotebookDocumentV1(
      metadata: ["foreign": .string("retained")],
      cells: [
        OwnedNotebookCell(
          id: "source-cell",
          code: nil,
          codeHash: "upstream-hash",
          name: nil,
          config: OwnedNotebookCellConfig(disabled: true)
        )
      ],
      appOptions: AppOptions(passthrough: ["future": .integer(7)]),
      header: nil
    )
    let backend = SyncRecordingBackend()
    let store = NotebookStore(backend: backend, document: NotebookDocumentState(owned: owned))
    let runtimeID = store.document.cells[0].runtimeID

    #expect(store.document.cells[0].sourceID == "source-cell")
    #expect(store.document.cells[0].code == "")
    #expect(store.document.cells[0].name == "_")
    #expect(store.document.cells[0].configuration.disabled)
    #expect(runtimeID.uuidString.dropFirst(14).first == "4")

    await store.send(
      .updateRuntime(
        cellID: runtimeID,
        runtime: CellRuntimeState(
          status: .running,
          stale: true,
          output: .string("not persisted"),
          console: [.string("transient")],
          lastExecutedCode: "old",
          widgetIDs: [UUID()]
        )
      )
    )
    await store.send(.setKernelSessionID("session-1"))
    #expect(!store.document.dirty)

    let saveDocument = store.document.persistentDocumentForSaving()
    #expect(saveDocument.metadata == owned.metadata)
    #expect(saveDocument.appOptions == owned.appOptions)
    #expect(saveDocument.cells[0].id == nil)
    #expect(saveDocument.cells[0].codeHash == nil)
    #expect(saveDocument.cells[0].code == "")
    #expect(store.document.cells[0].runtimeID == runtimeID)
  }

  @Test("Projection uses stable URIs, exact metadata names, and preserves unknown fields")
  func projectionEnvelope() {
    let documentID = UUID()
    let runtimeID = UUID()
    let cell = NotebookCellState(
      runtimeID: runtimeID,
      code: "value = 1",
      name: "named",
      configuration: CellConfiguration(column: 2, disabled: true, hideCode: true),
      projectionMetadata: ["foreignCell": .string("kept")]
    )
    let state = NotebookDocumentState(
      documentID: documentID,
      owned: OwnedNotebookDocumentV1(
        metadata: ["foreignNotebook": .bool(true)],
        cells: [],
        appOptions: AppOptions(passthrough: ["futureOption": .string("kept")])
      ),
      cells: [cell],
      projectionMetadata: ["foreignEnvelope": .integer(9)]
    )
    let snapshot = NotebookSynchronization.snapshot(state)

    #expect(snapshot.uri == "untitled:MarimoNative-\(documentID.uuidString)")
    #expect(snapshot.version == 1)
    #expect(snapshot.cells[0].uri == state.cellURI(cell))
    #expect(snapshot.cells[0].uri.hasPrefix("marimo-native-notebook-cell://"))
    #expect(snapshot.metadata["foreignEnvelope"] == .integer(9))
    #expect(
      snapshot.metadata["marimo"]?.object?["notebookMetadata"]?.object?["foreignNotebook"]
        == .bool(true)
    )
    let metadata = snapshot.cells[0].metadata
    #expect(metadata["foreignCell"] == .string("kept"))
    #expect(metadata["marimo"]?.object?["options"]?.object?["hide_code"] == .bool(true))
    #expect(
      metadata["marimoRuntime"]?.object?["stableId"] == .string(runtimeID.uuidString)
    )

    let noncanonical = URL(fileURLWithPath: "/tmp/../tmp/marimo-native.py")
    var fileState = state
    fileState.sourceURL = noncanonical
    #expect(
      fileState.notebookURI
        == noncanonical.resolvingSymlinksInPath().standardizedFileURL.absoluteString
    )
  }

  @Test("Committed text uses a UTF-16 incremental range and versions increase")
  func utf16IncrementalTextChange() async {
    let backend = SyncRecordingBackend()
    let cell = NotebookCellState(code: "a😀b\nz")
    let store = NotebookStore(
      backend: backend,
      document: NotebookDocumentState(cells: [cell])
    )
    await store.startBackend()
    await store.send(.updateCode(cellID: cell.runtimeID, code: "a😀Xb\nz"))
    await store.send(.updateCode(cellID: cell.runtimeID, code: "a😀XYb\nz"))

    let changes = await backend.events().compactMap { event -> (UInt64, NotebookTextChange)? in
      guard case .changed(_, let notebookVersion, .text(let change)) = event else { return nil }
      return (notebookVersion, change)
    }
    #expect(changes.count == 2)
    #expect(changes[0].0 == 2)
    #expect(changes[0].1.version == 2)
    #expect(changes[0].1.range?.start == LSPPosition(line: 0, character: 3))
    #expect(changes[0].1.range?.end == LSPPosition(line: 0, character: 3))
    #expect(changes[0].1.text == "X")
    #expect(changes[1].0 == 3)
    #expect(changes[1].1.version == 3)
  }

  @Test("Marked text is held until IME composition commits")
  func imeComposition() async {
    let backend = SyncRecordingBackend()
    let executable = URL(fileURLWithPath: "/bin/sh")
    let (preflight, _) = successfulPreflight(executableURL: executable)
    let store = NotebookStore(backend: backend, environmentPreflight: preflight)
    let cellID = store.document.cells[0].runtimeID
    await store.startBackend()
    await store.choosePythonExecutable(executable)
    store.chooseWorkingDirectory(URL(fileURLWithPath: "/tmp"))
    store.authorizeRunOnce()

    await store.send(
      .updateComposedCode(cellID: cellID, code: "かな", hasMarkedText: true)
    )
    await store.send(
      .runCell(
        cellID: cellID,
        executable: normalizedExecutableURL(executable).path,
        workingDirectory: canonicalURL(URL(fileURLWithPath: "/tmp")).path
      )
    )
    #expect(await backend.events().count == 1)
    #expect(!store.document.dirty)
    #expect(store.synchronizationError != nil)
    #expect(store.document.cells[0].editor.textDocumentVersion == 1)

    await store.send(
      .updateComposedCode(cellID: cellID, code: "かな", hasMarkedText: false)
    )
    let events = await backend.events()
    #expect(events.count == 2)
    guard case .changed(_, _, .text(let change)) = events[1] else {
      Issue.record("Committed composition did not produce one text change")
      return
    }
    #expect(change.text == "かな")
    #expect(store.document.dirty)
    #expect(store.document.cells[0].editor.textDocumentVersion == 2)

    await store.send(
      .runCell(
        cellID: cellID,
        executable: normalizedExecutableURL(executable).path,
        workingDirectory: canonicalURL(URL(fileURLWithPath: "/tmp")).path
      )
    )
    let ordered = await backend.events()
    guard ordered.count == 3 else {
      Issue.record("Expected execute after committed edit, got \(ordered.count) events")
      return
    }
    guard case .executed(_, let cells) = ordered[2] else {
      Issue.record("Execute overtook the committed didChange")
      return
    }
    #expect(cells == [NotebookExecutionCell(runtimeID: cellID, code: "かな")])
  }

  @Test("Untitled structural changes retain runtime and live session identities")
  func untitledStructureKeepsSession() async {
    let backend = SyncRecordingBackend()
    let store = NotebookStore(backend: backend)
    let originalID = store.document.cells[0].runtimeID
    let notebookURI = store.document.notebookURI
    await store.startBackend()
    await store.send(.setKernelSessionID("live-session"))
    await store.send(.updateCode(cellID: originalID, code: "edited = true"))
    #expect(store.document.cells[0].runtimeID == originalID)
    await store.send(.addCell)
    let addedID = store.document.cells[1].runtimeID
    #expect(store.document.cells[1].sourceID == nil)
    #expect(store.document.persistentDocumentForSaving().cells[1].id == nil)
    await store.send(.moveCell(addedID, to: 0))
    await store.recordSuccessfulSave()
    #expect(!store.document.dirty)
    #expect(store.document.cells.contains { $0.runtimeID == originalID })
    await store.send(.deleteCell(addedID))

    #expect(store.document.notebookURI == notebookURI)
    #expect(store.document.kernelSessionID == "live-session")
    #expect(store.document.cells[0].runtimeID == originalID)
    #expect(store.document.notebookVersion == 5)
    let events = await backend.events()
    #expect(
      events.contains(
        .deleted(notebookURI, "live-session", addedID.uuidString)
      )
    )
  }

  @Test("Cell data, notebook metadata, save, and close use their own notifications")
  func metadataSaveAndClose() async {
    let backend = SyncRecordingBackend()
    let store = NotebookStore(backend: backend)
    let cellID = store.document.cells[0].runtimeID
    await store.startBackend()
    await store.send(.updateName(cellID: cellID, name: "renamed"))
    await store.send(
      .updateConfiguration(
        cellID: cellID,
        configuration: CellConfiguration(disabled: true, hideCode: true)
      )
    )
    await store.send(.updateMetadata(["owner": .string("native")]))
    #expect(store.document.dirty)
    await store.recordSuccessfulSave()
    #expect(!store.document.dirty)
    await store.close()

    let events = await backend.events()
    #expect(events.contains { if case .changed(_, _, .cellData) = $0 { true } else { false } })
    #expect(
      events.contains { if case .changed(_, _, .notebookMetadata) = $0 { true } else { false } }
    )
    #expect(events.contains(.saved(store.document.notebookURI)))
    #expect(
      events.contains {
        guard case .closed(let uri, _) = $0 else { return false }
        return uri == store.document.notebookURI
      }
    )
  }
}

extension JSONValue {
  fileprivate var object: [String: JSONValue]? {
    guard case .object(let value) = self else { return nil }
    return value
  }
}
