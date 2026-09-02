import Foundation
import MarimoApplication
import MarimoBackend
import MarimoDomain
import MarimoEnvironment
import Testing

private actor SessionBackend: MarimoBackend {
  struct Execution: Sendable, Equatable {
    let notebookURI: String
    let cells: [NotebookExecutionCell]
  }

  private var ready = false
  private var executions: [Execution] = []
  private var listCount = 0
  private var sessions: [MarimoSessionInfo] = []
  private var replays: [MarimoCellReplay] = []
  private let stream: AsyncStream<MarimoBackendEvent>
  private let continuation: AsyncStream<MarimoBackendEvent>.Continuation

  init() {
    (stream, continuation) = AsyncStream.makeStream()
  }

  func status() -> BackendStatus { ready ? .ready : .unavailable }
  func start() { ready = true }
  func parseNotebook(source _: String) -> NotebookParseOutcome { .convertible }
  func backendEvents() -> AsyncStream<MarimoBackendEvent> { stream }
  func execute(
    notebookURI: String,
    executable _: String,
    workingDirectory _: String,
    cells: [NotebookExecutionCell]
  ) {
    executions.append(Execution(notebookURI: notebookURI, cells: cells))
  }
  func listSessions() -> [MarimoSessionInfo] {
    listCount += 1
    return sessions
  }
  func readNotebookOutputs(notebookURI _: String) -> [MarimoCellReplay] { replays }
  func shutdown() { ready = false }

  func emit(_ event: MarimoBackendEvent) { continuation.yield(event) }
  func recordedExecutions() -> [Execution] { executions }
  func recordedListCount() -> Int { listCount }
  func setSessions(_ value: [MarimoSessionInfo]) { sessions = value }
  func setReplays(_ value: [MarimoCellReplay]) { replays = value }
}

private actor BlockingSynchronizationBackend: MarimoBackend {
  private var ready = false
  private var changeStarted = false
  private var releaseChange: CheckedContinuation<Void, Never>?
  private var order: [String] = []

  func status() -> BackendStatus { ready ? .ready : .unavailable }
  func start() { ready = true }
  func parseNotebook(source _: String) -> NotebookParseOutcome { .convertible }
  func didChangeNotebook(uri _: String, version _: UInt64, change _: NotebookSyncChange) async {
    changeStarted = true
    order.append("change-started")
    await withCheckedContinuation { releaseChange = $0 }
    order.append("change-finished")
  }
  func execute(
    notebookURI _: String,
    executable _: String,
    workingDirectory _: String,
    cells _: [NotebookExecutionCell]
  ) {
    order.append("execute")
  }
  func shutdown() { ready = false }

  func hasStartedChange() -> Bool { changeStarted }
  func release() {
    releaseChange?.resume()
    releaseChange = nil
  }
  func recordedOrder() -> [String] { order }
}

@Suite("Notebook session lifecycle", .serialized)
@MainActor
struct NotebookSessionTests {
  @Test("Execute waits for the committed didChange to finish")
  func executeFlushesCommittedText() async {
    let executableURL = URL(fileURLWithPath: "/bin/sh")
    let (preflight, _) = successfulPreflight(executableURL: executableURL)
    let backend = BlockingSynchronizationBackend()
    let store = NotebookStore(backend: backend, environmentPreflight: preflight)
    await store.startBackend()
    await store.choosePythonExecutable(executableURL)
    store.chooseWorkingDirectory(URL(fileURLWithPath: "/tmp"))
    let cellID = store.document.cells[0].runtimeID
    let edit = Task { @MainActor in
      await store.send(.updateCode(cellID: cellID, code: "committed = true"))
    }
    while !(await backend.hasStartedChange()) { await Task.yield() }
    store.authorizeRunOnce()
    let run = Task { @MainActor in
      await store.send(
        .runCell(
          cellID: cellID,
          executable: normalizedExecutableURL(executableURL).path,
          workingDirectory: canonicalURL(URL(fileURLWithPath: "/tmp")).path
        )
      )
    }
    try? await Task.sleep(for: .milliseconds(20))
    #expect(await backend.recordedOrder() == ["change-started"])
    await backend.release()
    await edit.value
    await run.value
    #expect(await backend.recordedOrder() == ["change-started", "change-finished", "execute"])
  }

  @Test("Run Cell sends only current editor source and completes only on completed-run")
  func runCellLifecycle() async throws {
    let (store, backend, executable, workingDirectory) = await configuredStore()
    let first = store.document.cells[0].runtimeID
    let foreign = UUID()

    await store.send(.updateCode(cellID: first, code: "value = 42"))
    #expect(store.document.dirty)
    store.authorizeRunOnce()
    await store.send(
      .runCell(
        cellID: first,
        executable: executable,
        workingDirectory: workingDirectory
      )
    )
    #expect(store.sessionState == .starting)
    #expect(
      await backend.recordedExecutions().first?.cells
        == [NotebookExecutionCell(runtimeID: first, code: "value = 42")]
    )

    await backend.emit(
      .kernel(
        MarimoKernelEvent(
          notebookURI: "file:///foreign.py",
          sessionID: "foreign",
          operation: "completed-run",
          payload: [:]
        )
      )
    )
    await backend.emit(
      .kernel(
        MarimoKernelEvent(
          notebookURI: store.document.notebookURI,
          sessionID: "session-1",
          operation: "kernel-ready",
          payload: [:]
        )
      )
    )
    await eventually { store.document.kernelSessionID == "session-1" }
    #expect(store.sessionState == .running)
    await backend.emit(
      .kernel(
        MarimoKernelEvent(
          notebookURI: store.document.notebookURI,
          sessionID: "session-1",
          operation: "cell-op",
          payload: ["cell_id": .string(first.uuidString), "status": .string("running")]
        )
      )
    )
    await eventually { store.document.cells[0].runtime.status == .running }
    #expect(store.sessionState == .running)
    #expect(store.document.dirty)

    await backend.emit(
      .kernel(
        MarimoKernelEvent(
          notebookURI: store.document.notebookURI,
          sessionID: "old-session",
          operation: "cell-op",
          payload: ["cell_id": .string(foreign.uuidString), "status": .string("running")]
        )
      )
    )
    await backend.emit(
      .kernel(
        MarimoKernelEvent(
          notebookURI: store.document.notebookURI,
          sessionID: "session-1",
          operation: "completed-run",
          payload: [:]
        )
      )
    )
    await eventually { store.sessionState == .idle }
  }

  @Test("Run All preserves current order and includes every cell")
  func runAllPayload() async {
    let (store, backend, executable, workingDirectory) = await configuredStore()
    let first = store.document.cells[0].runtimeID
    await store.send(.updateCode(cellID: first, code: "first = 1"))
    await store.send(.addCell)
    let second = store.document.cells[1].runtimeID
    await store.send(.updateCode(cellID: second, code: "second = first + 1"))
    await store.send(
      .updateConfiguration(
        cellID: second,
        configuration: CellConfiguration(disabled: true)
      )
    )
    store.authorizeRunOnce()
    await store.send(.runAll(executable: executable, workingDirectory: workingDirectory))

    #expect(
      await backend.recordedExecutions().first?.cells == [
        NotebookExecutionCell(runtimeID: first, code: "first = 1"),
        NotebookExecutionCell(runtimeID: second, code: "second = first + 1"),
      ]
    )
  }

  @Test("Trust choice resumes the exact pending Run All request")
  func trustResumesPendingRunAll() async {
    let (store, backend, _, _) = await configuredStore()
    await store.requestRunAll()
    #expect(store.executionTrustPromptPresented)
    #expect(await backend.recordedExecutions().isEmpty)
    store.authorizeRunOnce()
    await eventually { !(store.executionTrustPromptPresented) }
    let deadline = ContinuousClock.now.advanced(by: .seconds(1))
    while await backend.recordedExecutions().isEmpty, ContinuousClock.now < deadline {
      await Task.yield()
    }
    #expect(await backend.recordedExecutions().count == 1)
  }

  @Test("cell-op applies one partial update without clearing omitted fields")
  func partialCellOperation() async throws {
    let (store, backend, _, _) = await configuredStore()
    let cellID = store.document.cells[0].runtimeID
    await store.send(
      .updateRuntime(
        cellID: cellID,
        runtime: CellRuntimeState(
          status: .idle,
          stale: false,
          output: .string("old"),
          console: [.string("existing")],
          widgetIDs: [UUID()]
        )
      )
    )
    await backend.emit(
      .kernel(
        MarimoKernelEvent(
          notebookURI: store.document.notebookURI,
          sessionID: "session-1",
          operation: "cell-op",
          payload: [
            "cell_id": .string(cellID.uuidString),
            "console": .array([.string("one"), .string("two")]),
            "status": .string("queued"),
            "stale_inputs": .bool(true),
          ]
        )
      )
    )
    await eventually { store.document.cells[0].runtime.status == .queued }
    #expect(store.document.cells[0].runtime.output == .string("old"))
    #expect(
      store.document.cells[0].runtime.console
        == [.string("existing"), .string("one"), .string("two")]
    )
    #expect(store.document.cells[0].runtime.stale)
    #expect(store.document.cells[0].runtime.widgetIDs.isEmpty)

    await backend.emit(
      .kernel(
        MarimoKernelEvent(
          notebookURI: store.document.notebookURI,
          sessionID: "session-1",
          operation: "cell-op",
          payload: [
            "cell_id": .string(cellID.uuidString),
            "output": .object(["data": .string("new")]),
            "console": .array([]),
          ]
        )
      )
    )
    await eventually { store.document.cells[0].runtime.console.isEmpty }
    #expect(store.document.cells[0].runtime.output == .object(["data": .string("new")]))

    await backend.emit(
      .kernel(
        MarimoKernelEvent(
          notebookURI: store.document.notebookURI,
          sessionID: "session-1",
          operation: "cell-op",
          payload: [
            "cell_id": .string(cellID.uuidString),
            "console": .string("single"),
            "status": .string("disabled-transitively"),
          ]
        )
      )
    )
    await eventually { store.document.cells[0].runtime.status == .disabledTransitively }
    #expect(store.document.cells[0].runtime.console == [.string("single")])

    let unchanged = store.document.cells[0].runtime
    await backend.emit(
      .kernel(
        MarimoKernelEvent(
          notebookURI: store.document.notebookURI,
          sessionID: "session-1",
          operation: "cell-op",
          payload: ["cell_id": .string(UUID().uuidString), "output": .string("ignored")]
        )
      )
    )
    await Task.yield()
    #expect(store.document.cells[0].runtime == unchanged)
  }

  @Test("Session lookup runs once after timeout and fails when no URI matches")
  func sessionResolutionFallback() async throws {
    let (store, backend, executable, workingDirectory) = await configuredStore(
      timeout: .milliseconds(10)
    )
    store.authorizeRunOnce()
    await store.send(
      .runCell(
        cellID: store.document.cells[0].runtimeID,
        executable: executable,
        workingDirectory: workingDirectory
      )
    )
    await eventually { if case .failed = store.sessionState { true } else { false } }
    #expect(await backend.recordedListCount() == 2)
  }

  @Test("Session lookup accepts the one matching notebook after timeout")
  func sessionResolutionFallbackFindsMatch() async {
    let (store, backend, executable, workingDirectory) = await configuredStore(
      timeout: .milliseconds(10)
    )
    await backend.setSessions([
      MarimoSessionInfo(
        sessionID: "fallback-session",
        notebookURI: store.document.notebookURI,
        executable: executable,
        workingDirectory: workingDirectory,
        status: "running"
      )
    ])
    store.authorizeRunOnce()
    await store.send(
      .runCell(
        cellID: store.document.cells[0].runtimeID,
        executable: executable,
        workingDirectory: workingDirectory
      )
    )
    await eventually { store.document.kernelSessionID == "fallback-session" }
    #expect(store.sessionState == .running)
    #expect(await backend.recordedListCount() == 2)
  }

  @Test("Kernel startup error records its body and enters failed")
  func kernelStartupError() async {
    let (store, backend, _, _) = await configuredStore()
    await backend.emit(
      .kernel(
        MarimoKernelEvent(
          notebookURI: store.document.notebookURI,
          sessionID: "session-error",
          operation: "kernel-startup-error",
          payload: ["error": .string("missing runtime dependency")]
        )
      )
    )
    await eventually { store.sessionState == .failed("missing runtime dependency") }
    #expect(store.document.kernelSessionID == "session-error")
  }

  @Test("Reattach restores live output and session identity")
  func reattach() async throws {
    let backend = SessionBackend()
    let cell = NotebookCellState(code: "value = 1")
    let document = NotebookDocumentState(cells: [cell])
    await backend.setSessions([
      MarimoSessionInfo(
        sessionID: "reattached",
        notebookURI: document.notebookURI,
        executable: "/tmp/python",
        workingDirectory: "/tmp",
        status: "idle"
      )
    ])
    await backend.setReplays([
      MarimoCellReplay(
        payload: [
          "cell_id": .string(cell.runtimeID.uuidString),
          "output": .string("restored"),
          "status": .string("idle"),
        ],
        executedSource: "value = 1"
      )
    ])
    let store = NotebookStore(backend: backend, document: document)
    await store.startBackend()
    #expect(store.document.kernelSessionID == "reattached")
    #expect(store.sessionState == .idle)
    #expect(store.document.cells[0].runtime.output == .string("restored"))
    #expect(store.document.cells[0].runtime.lastExecutedCode == "value = 1")
  }

  private func configuredStore(
    timeout: Duration = .seconds(15)
  ) async -> (NotebookStore, SessionBackend, String, String) {
    let executableURL = URL(fileURLWithPath: "/bin/sh")
    let (preflight, _) = successfulPreflight(executableURL: executableURL)
    let backend = SessionBackend()
    let store = NotebookStore(
      backend: backend,
      environmentPreflight: preflight,
      sessionResolutionTimeout: timeout
    )
    await store.startBackend()
    await store.choosePythonExecutable(executableURL)
    store.chooseWorkingDirectory(URL(fileURLWithPath: "/tmp"))
    return (
      store,
      backend,
      normalizedExecutableURL(executableURL).path,
      canonicalURL(URL(fileURLWithPath: "/tmp")).path
    )
  }

  private func eventually(
    _ condition: @escaping @MainActor () -> Bool
  ) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(1))
    while !condition(), ContinuousClock.now < deadline {
      await Task.yield()
    }
    #expect(condition())
  }
}
