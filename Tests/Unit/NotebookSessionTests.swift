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
  private var interruptCalls: [(String, String)] = []
  private var restartCalls: [(String, String, String, Bool)] = []
  private var stdinCalls: [(String, String, String)] = []
  private var openCount = 0
  private var startCount = 0
  private let stream: AsyncStream<MarimoBackendEvent>
  private let continuation: AsyncStream<MarimoBackendEvent>.Continuation

  init() {
    (stream, continuation) = AsyncStream.makeStream()
  }

  func status() -> BackendStatus { ready ? .ready : .unavailable }
  func start() {
    ready = true
    startCount += 1
  }
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
  func didOpenNotebook(_: NotebookSyncSnapshot) { openCount += 1 }
  func interrupt(notebookURI: String, kernelSessionID: String) {
    interruptCalls.append((notebookURI, kernelSessionID))
  }
  func restartSession(
    notebookURI: String,
    executable: String,
    workingDirectory: String,
    createIfMissing: Bool
  ) {
    restartCalls.append((notebookURI, executable, workingDirectory, createIfMissing))
  }
  func sendStdin(notebookURI: String, kernelSessionID: String, text: String) {
    stdinCalls.append((notebookURI, kernelSessionID, text))
  }
  func shutdown() { ready = false }

  func emit(_ event: MarimoBackendEvent) { continuation.yield(event) }
  func recordedExecutions() -> [Execution] { executions }
  func recordedListCount() -> Int { listCount }
  func setSessions(_ value: [MarimoSessionInfo]) { sessions = value }
  func setReplays(_ value: [MarimoCellReplay]) { replays = value }
  func recordedInterrupts() -> [(String, String)] { interruptCalls }
  func recordedRestarts() -> [(String, String, String, Bool)] { restartCalls }
  func recordedStdin() -> [(String, String, String)] { stdinCalls }
  func recordedOpenCount() -> Int { openCount }
  func recordedStartCount() -> Int { startCount }
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

  @Test("Interrupt is sent once and exposes Force Restart only after timeout")
  func interruptIsSingleShot() async {
    let (store, backend, executable, workingDirectory) = await configuredStore(
      interruptTimeout: .milliseconds(10)
    )
    await beginRunning(
      store: store,
      backend: backend,
      executable: executable,
      workingDirectory: workingDirectory
    )

    await store.requestInterrupt()
    await store.requestInterrupt()
    #expect(store.sessionState == .interrupting)
    #expect(await backend.recordedInterrupts().count == 1)
    #expect(!(store.forceRestartAvailable))
    await eventually { store.forceRestartAvailable }

    await backend.emit(
      .kernel(
        MarimoKernelEvent(
          notebookURI: store.document.notebookURI,
          sessionID: "session-running",
          operation: "interrupted",
          payload: [:]
        )
      )
    )
    await eventually { store.sessionState == .idle }
    #expect(!(store.forceRestartAvailable))
  }

  @Test("Session-bound operations require the current kernel session")
  func sessionBoundOperationsRequireCurrentSession() async {
    let (store, backend, _, _) = await configuredStore()
    let cellID = store.document.cells[0].runtimeID
    await store.send(
      .updateRuntime(
        cellID: cellID,
        runtime: CellRuntimeState(
          stdinPrompt: StdinPromptState(prompt: "Input", password: false)
        )
      )
    )

    await store.requestInterrupt()
    await store.submitStdin(cellID: cellID, text: "ignored")
    #expect(await backend.recordedInterrupts().isEmpty)
    #expect(await backend.recordedStdin().isEmpty)
    #expect(store.document.cells[0].runtime.stdinPrompt?.submitted == false)
  }

  @Test("Restart invalidates the old session and clears only transient kernel state")
  func restartClearsKernelState() async {
    let (store, backend, executable, workingDirectory) = await configuredStore()
    await beginRunning(
      store: store,
      backend: backend,
      executable: executable,
      workingDirectory: workingDirectory
    )
    let cellID = store.document.cells[0].runtimeID
    store.focusEditor(cellID)
    await store.send(
      .updateRuntime(
        cellID: cellID,
        runtime: CellRuntimeState(
          status: .running,
          output: .string("old output"),
          widgetIDs: [UUID()],
          stdinPrompt: StdinPromptState(prompt: "secret", password: true)
        )
      )
    )

    await store.requestRestartKernel()
    #expect(store.document.kernelSessionID == nil)
    #expect(store.sessionState == .restarting)
    #expect(store.document.cells[0].code == "value = 1")
    #expect(store.document.selectedCellID == cellID)
    #expect(store.focusedCellID == cellID)
    #expect(store.document.cells[0].runtime == CellRuntimeState())
    let restart = await backend.recordedRestarts().first
    #expect(restart?.0 == store.document.notebookURI)
    #expect(restart?.1 == executable)
    #expect(restart?.2 == workingDirectory)
    #expect(restart?.3 == false)

    await backend.emit(
      .sessionsChanged([
        MarimoSessionInfo(
          sessionID: "session-restarted",
          notebookURI: store.document.notebookURI,
          executable: executable,
          workingDirectory: workingDirectory,
          status: "idle"
        )
      ])
    )
    await eventually { store.sessionState == .idle }
    #expect(store.document.kernelSessionID == "session-restarted")
  }

  @Test("Password stdin keeps only prompt metadata and disables after one send")
  func secureStdin() async {
    let (store, backend, executable, workingDirectory) = await configuredStore()
    await beginRunning(
      store: store,
      backend: backend,
      executable: executable,
      workingDirectory: workingDirectory
    )
    let cellID = store.document.cells[0].runtimeID
    await backend.emit(
      .kernel(
        MarimoKernelEvent(
          notebookURI: store.document.notebookURI,
          sessionID: "session-running",
          operation: "cell-op",
          payload: [
            "cell_id": .string(cellID.uuidString),
            "console": .object([
              "channel": .string("stdin"),
              "mimetype": .string("text/password"),
              "data": .string("Password: "),
            ]),
          ]
        )
      )
    )
    await eventually { store.document.cells[0].runtime.stdinPrompt != nil }
    #expect(store.document.cells[0].runtime.stdinPrompt?.password == true)

    await store.submitStdin(cellID: cellID, text: "not-restored-secret")
    await store.submitStdin(cellID: cellID, text: "duplicate")
    #expect(store.document.cells[0].runtime.stdinPrompt?.submitted == true)
    #expect(!String(describing: store.document).contains("not-restored-secret"))
    let sent = await backend.recordedStdin()
    #expect(sent.count == 1)
    #expect(sent.first?.1 == "session-running")
    #expect(sent.first?.2 == "not-restored-secret")
  }

  @Test("Backend recovery preserves the dirty editor buffer and reopens it")
  func backendRecoveryPreservesDocument() async {
    let (store, backend, _, _) = await configuredStore()
    let cellID = store.document.cells[0].runtimeID
    await store.send(.updateCode(cellID: cellID, code: "unsaved = 99"))
    let opensBefore = await backend.recordedOpenCount()

    await backend.emit(.disconnected)
    await eventually { store.backendStatus == .unavailable }
    #expect(store.document.cells[0].code == "unsaved = 99")
    #expect(store.document.dirty)
    await backend.emit(.restarted)
    await eventually { store.backendStatus == .ready }
    await eventually { store.sessionState == .notStarted }
    #expect(await backend.recordedOpenCount() == opensBefore + 1)
    #expect(store.document.cells[0].code == "unsaved = 99")
    #expect(store.document.dirty)

    await backend.emit(.automaticRestartStopped(stderr: ["fatal sidecar error"]))
    await eventually { store.backendRecoveryStopped }
    #expect(store.backendLogs == ["fatal sidecar error"])
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
    timeout: Duration = .seconds(15),
    interruptTimeout: Duration = .seconds(10)
  ) async -> (NotebookStore, SessionBackend, String, String) {
    let executableURL = URL(fileURLWithPath: "/bin/sh")
    let (preflight, _) = successfulPreflight(executableURL: executableURL)
    let backend = SessionBackend()
    let store = NotebookStore(
      backend: backend,
      environmentPreflight: preflight,
      sessionResolutionTimeout: timeout,
      interruptTimeout: interruptTimeout
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

  private func beginRunning(
    store: NotebookStore,
    backend: SessionBackend,
    executable: String,
    workingDirectory: String
  ) async {
    let cellID = store.document.cells[0].runtimeID
    await store.send(.updateCode(cellID: cellID, code: "value = 1"))
    store.authorizeRunOnce()
    await store.send(
      .runCell(cellID: cellID, executable: executable, workingDirectory: workingDirectory)
    )
    await backend.emit(
      .kernel(
        MarimoKernelEvent(
          notebookURI: store.document.notebookURI,
          sessionID: "session-running",
          operation: "kernel-ready",
          payload: [:]
        )
      )
    )
    await eventually { store.sessionState == .running }
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
