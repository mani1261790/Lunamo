import Foundation
import MarimoBackend
import MarimoDomain
import MarimoEnvironment
import OSLog

enum PendingRunRequest: Sendable, Equatable {
  case cell(UUID, followUp: CellRunFollowUp)
  case all
}

enum CellRunFollowUp: Sendable, Equatable {
  case stay
  case advance
  case insertBelow
}

extension NotebookStore {
  public func refreshBackendStatus() async {
    backendStatus = await backend.status()
  }

  public func startBackend() async {
    do {
      startBackendEventRouting()
      try await backend.start()
      backendStatus = await backend.status()
      backendRecoveryStopped = false
      if backendStatus == .ready {
        try await synchronizeOpenDocument()
        await reattachSessionIfAvailable()
      }
    } catch {
      backendStatus = .unavailable
      synchronizationError = String(describing: error)
    }
  }

  public func shutdownBackend() async {
    try? await closeDocumentSynchronization()
    await backend.shutdown()
    backendStatus = .unavailable
    resetSessionState(to: .closed)
    backendEventTask?.cancel()
    backendEventTask = nil
  }

  public var sessionAllowsRun: Bool {
    switch sessionState {
    case .notStarted, .idle: true
    case .starting, .running, .interrupting, .restarting, .failed, .closed: false
    }
  }

  public var sessionStatusLabel: String {
    switch sessionState {
    case .notStarted: "Not Started"
    case .starting: "Starting"
    case .idle: "Idle"
    case .running: "Running"
    case .interrupting: "Interrupting"
    case .restarting: "Restarting"
    case .failed(let message): "Failed: \(message)"
    case .closed: "Closed"
    }
  }

  public func requestRunCell(_ cellID: UUID, advance: Bool = false, insertBelow: Bool = false)
    async
  {
    let followUp: CellRunFollowUp = insertBelow ? .insertBelow : (advance ? .advance : .stay)
    pendingRunRequest = .cell(cellID, followUp: followUp)
    guard await requestExecutionAuthorization() else { return }
    await executePendingRun()
  }

  public func requestRunAll() async {
    pendingRunRequest = .all
    guard await requestExecutionAuthorization() else { return }
    await executePendingRun()
  }

  func resumePendingRun() {
    guard pendingRunRequest != nil else { return }
    Task { @MainActor [weak self] in await self?.executePendingRun() }
  }

  func executePendingRun() async {
    guard let request = pendingRunRequest else { return }
    guard case .ready(let details, let workingDirectory) = environmentState else { return }
    pendingRunRequest = nil
    switch request {
    case .cell(let cellID, let followUp):
      await send(
        .runCell(
          cellID: cellID,
          executable: details.executableURL.path,
          workingDirectory: workingDirectory.path
        )
      )
      guard synchronizationError == nil else { return }
      applyRunFollowUp(followUp, after: cellID)
    case .all:
      await send(
        .runAll(
          executable: details.executableURL.path,
          workingDirectory: workingDirectory.path
        )
      )
    }
  }

  func performRun(cellIDs: [UUID], executable: String, workingDirectory: String) async throws {
    let indices = cellIDs.compactMap { id in
      document.cells.firstIndex { $0.runtimeID == id }
    }
    guard indices.count == cellIDs.count, !indices.isEmpty else {
      throw NotebookStoreError.noCellsToExecute
    }
    if let composing = indices.first(where: { document.cells[$0].editor.hasMarkedText }) {
      throw NotebookStoreError.compositionActive(document.cells[composing].runtimeID)
    }
    guard case .ready(let details, let configuredWorkingDirectory) = environmentState else {
      throw NotebookStoreError.environmentNotReady
    }
    guard
      normalizedExecutableURL(URL(fileURLWithPath: executable)).path == details.executableURL.path,
      canonicalURL(URL(fileURLWithPath: workingDirectory)).path == configuredWorkingDirectory.path
    else { throw NotebookStoreError.environmentMismatch }
    guard await consumeExecutionAuthorization() else {
      throw NotebookStoreError.executionNotTrusted
    }

    try await flushCommittedTextChanges()
    let cells = indices.map {
      NotebookExecutionCell(
        runtimeID: document.cells[$0].runtimeID,
        code: document.cells[$0].code
      )
    }
    for index in indices {
      document.cells[index].runtime.lastExecutedCode = document.cells[index].code
    }

    if document.kernelSessionID == nil {
      sessionState = .starting
      scheduleSessionResolution()
    } else {
      sessionState = .running
    }
    runAwaitingCompletion = true
    do {
      try await backend.execute(
        notebookURI: document.notebookURI,
        executable: executable,
        workingDirectory: workingDirectory,
        cells: cells
      )
    } catch {
      sessionResolutionTask?.cancel()
      sessionResolutionTask = nil
      runAwaitingCompletion = false
      sessionState = .failed(String(describing: error))
      throw error
    }
  }

  func flushCommittedTextChanges() async throws {
    for task in Array(pendingTextSynchronizations.values) {
      try await task.value
    }
  }

  func startBackendEventRouting() {
    guard backendEventTask == nil else { return }
    let backend = self.backend
    backendEventTask = Task { @MainActor [weak self] in
      let events = await backend.backendEvents()
      for await event in events {
        guard !Task.isCancelled, let self else { return }
        self.applyBackendEvent(event)
      }
    }
  }

  func reattachSessionIfAvailable() async {
    guard document.kernelSessionID == nil else { return }
    do {
      let sessions = try await backend.listSessions()
      guard let match = sessions.first(where: { $0.notebookURI == document.notebookURI }) else {
        if sessionState != .closed { sessionState = .notStarted }
        return
      }
      acceptSession(match.sessionID)
      runAwaitingCompletion = false
      sessionState = match.status == "running" ? .running : .idle
      for replay in try await backend.readNotebookOutputs(notebookURI: document.notebookURI) {
        applyCellOperation(replay.payload, executedSource: replay.executedSource)
      }
    } catch {
      NotebookSessionLog.logger.debug("No compatible live session was reattached")
    }
  }

  func resetSessionState(to state: NotebookSessionState) {
    sessionResolutionTask?.cancel()
    sessionResolutionTask = nil
    pendingRunRequest = nil
    runAwaitingCompletion = false
    interruptTimeoutTask?.cancel()
    interruptTimeoutTask = nil
    forceRestartAvailable = false
    document.kernelSessionID = nil
    sessionState = state
    for index in document.cells.indices {
      document.cells[index].runtime.status = .idle
      document.cells[index].runtime.widgetIDs = []
      document.cells[index].runtime.stdinPrompt = nil
    }
  }

  private func applyRunFollowUp(_ followUp: CellRunFollowUp, after cellID: UUID) {
    guard let index = document.cells.firstIndex(where: { $0.runtimeID == cellID }) else { return }
    switch followUp {
    case .stay:
      break
    case .advance:
      if document.cells.indices.contains(index + 1) {
        document.selectedCellID = document.cells[index + 1].runtimeID
        focusedCellID = document.cells[index + 1].runtimeID
      }
    case .insertBelow:
      Task { @MainActor [weak self] in
        guard let self else { return }
        await self.send(.insertCell(after: cellID))
        if let selected = self.document.selectedCellID { self.focusEditor(selected) }
      }
    }
  }

  func scheduleSessionResolution() {
    sessionResolutionTask?.cancel()
    let timeout = sessionResolutionTimeout
    sessionResolutionTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: timeout)
      guard !Task.isCancelled, let self, self.document.kernelSessionID == nil,
        self.sessionState == .starting
      else { return }
      do {
        let sessions = try await self.backend.listSessions()
        if let match = sessions.first(where: { $0.notebookURI == self.document.notebookURI }) {
          self.acceptSession(match.sessionID)
          self.sessionState =
            self.runAwaitingCompletion || match.status == "running" ? .running : .idle
        } else {
          self.sessionState = .failed("The kernel session could not be identified.")
        }
      } catch {
        self.sessionState = .failed("The kernel session could not be identified: \(error)")
      }
      self.sessionResolutionTask = nil
    }
  }

  func applyBackendEvent(_ event: MarimoBackendEvent) {
    switch event {
    case .sessionsChanged(let sessions):
      guard document.kernelSessionID == nil,
        sessionState == .starting || sessionState == .restarting
      else { return }
      guard let match = sessions.first(where: { $0.notebookURI == document.notebookURI }) else {
        return
      }
      let wasRestarting = sessionState == .restarting
      acceptSession(match.sessionID)
      if wasRestarting {
        sessionState = match.status == "running" ? .running : .idle
      }
    case .kernel(let event):
      guard event.notebookURI == document.notebookURI else { return }
      if let current = document.kernelSessionID {
        guard current == event.sessionID else { return }
      } else {
        acceptSession(event.sessionID)
      }
      switch event.operation {
      case "kernel-ready":
        if sessionState == .starting || sessionState == .restarting {
          sessionState = runAwaitingCompletion ? .running : .idle
        }
      case "cell-op":
        applyCellOperation(event.payload, executedSource: nil)
      case "completed-run", "interrupted":
        interruptTimeoutTask?.cancel()
        interruptTimeoutTask = nil
        forceRestartAvailable = false
        runAwaitingCompletion = false
        sessionState = .idle
      case "kernel-startup-error":
        let message = event.payload.string(for: "error") ?? "Kernel startup failed."
        runAwaitingCompletion = false
        sessionState = .failed(message)
      default:
        break
      }
    case .disconnected:
      handleBackendDisconnected()
    case .restarted:
      handleBackendRestarted()
    case .automaticRestartStopped(let stderr):
      handleAutomaticRestartStopped(stderr: stderr)
    }
  }

  private func acceptSession(_ sessionID: String) {
    guard document.kernelSessionID != sessionID else { return }
    document.kernelSessionID = sessionID
    sessionResolutionTask?.cancel()
    sessionResolutionTask = nil
    for index in document.cells.indices {
      document.cells[index].runtime.status = .idle
      document.cells[index].runtime.widgetIDs = []
      document.cells[index].runtime.stdinPrompt = nil
    }
  }

  private func applyCellOperation(
    _ payload: [String: JSONValue],
    executedSource: String?
  ) {
    guard let cellID = payload.string(for: "cell_id"),
      let index = document.cells.firstIndex(where: { $0.runtimeID.uuidString == cellID })
    else {
      NotebookSessionLog.logger.debug("Ignoring cell-op for an unknown cell")
      return
    }
    var runtime = document.cells[index].runtime
    if payload.keys.contains("output") {
      runtime.output = payload["output"] == .null ? nil : payload["output"]
    }
    if let console = payload["console"] {
      if let prompt = stdinPrompt(from: console) { runtime.stdinPrompt = prompt }
      switch console {
      case .array(let values):
        if values.isEmpty {
          runtime.console.removeAll()
        } else {
          runtime.console.append(contentsOf: values)
        }
      case .null:
        break
      default:
        runtime.console.append(console)
      }
    }
    if let status = payload.string(for: "status"), let accepted = ExecutionStatus(rawValue: status),
      accepted != .error
    {
      runtime.status = accepted
      if accepted == .queued || accepted == .running { sessionState = .running }
    }
    if let stale = payload.bool(for: "stale_inputs") { runtime.stale = stale }
    if let executedSource { runtime.lastExecutedCode = executedSource }
    document.cells[index].runtime = runtime
  }

  private func stdinPrompt(from value: JSONValue) -> StdinPromptState? {
    let values: [JSONValue]
    if case .array(let array) = value { values = array } else { values = [value] }
    for value in values.reversed() {
      guard case .object(let object) = value,
        object.string(for: "channel") == "stdin"
      else { continue }
      return StdinPromptState(
        prompt: object.string(for: "data") ?? "",
        password: object.string(for: "mimetype") == "text/password"
      )
    }
    return nil
  }
}

private enum NotebookSessionLog {
  static let logger = Logger(subsystem: "MarimoNative", category: "NotebookSession")
}

extension Dictionary where Key == String, Value == JSONValue {
  func string(for key: String) -> String? {
    guard case .string(let value)? = self[key] else { return nil }
    return value
  }

  func bool(for key: String) -> Bool? {
    guard case .bool(let value)? = self[key] else { return nil }
    return value
  }
}
