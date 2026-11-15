import Foundation
import MarimoBackend
import MarimoDomain

extension NotebookStore {
  func presentBackendStartError(_ error: any Error) {
    presentError(
      code: .lspStart,
      cause: error.localizedDescription,
      target: "Bundled sidecar",
      recoveryActions: ["Restart Backend", "Open Logs"]
    )
  }

  func presentKernelStartError(_ message: String, sessionID: String) {
    presentError(
      code: .kernelStart,
      cause: message,
      target: sessionID,
      recoveryActions: ["Restart Kernel", "Choose Python Environment"]
    )
  }

  public var sessionAllowsInterrupt: Bool {
    (sessionState == .running || sessionState == .interrupting) && document.kernelSessionID != nil
  }

  public var sessionAllowsRestart: Bool {
    guard backendStatus == .ready else { return false }
    guard case .ready = environmentState else { return false }
    // A failed start/restart may have already cleared its session identifier.
    // Keep explicit recovery available without enabling automatic execution.
    if case .failed = sessionState { return true }
    guard document.kernelSessionID != nil else { return false }
    return sessionState != .starting && sessionState != .restarting && sessionState != .closed
  }

  public func requestInterrupt() async {
    guard sessionState == .running, sessionAllowsInterrupt, interruptTimeoutTask == nil,
      let sessionID = document.kernelSessionID
    else { return }

    sessionState = .interrupting
    forceRestartAvailable = false
    let timeout = interruptTimeout
    interruptTimeoutTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: timeout)
      guard !Task.isCancelled, let self, self.sessionState == .interrupting else { return }
      self.forceRestartAvailable = true
      self.presentError(
        code: .kernelInterrupt,
        cause: "The kernel did not acknowledge Interrupt within the bounded timeout.",
        target: self.document.kernelSessionID ?? self.document.notebookURI,
        recoveryActions: ["Force Restart Kernel", "Open Logs"]
      )
    }
    do {
      try await backend.interrupt(
        notebookURI: document.notebookURI,
        kernelSessionID: sessionID
      )
    } catch {
      interruptTimeoutTask?.cancel()
      interruptTimeoutTask = nil
      forceRestartAvailable = false
      sessionState = .failed(String(describing: error))
      synchronizationError = String(describing: error)
    }
  }

  public func requestRestartKernel(createIfMissing: Bool = false) async {
    guard sessionAllowsRestart else { return }
    guard case .ready(let details, let workingDirectory) = environmentState else { return }

    let needsSessionCreation = document.kernelSessionID == nil
    clearRuntimePackageAlert()

    interruptTimeoutTask?.cancel()
    interruptTimeoutTask = nil
    forceRestartAvailable = false
    runAwaitingCompletion = false
    completionRefreshTask?.cancel()
    completionRefreshTask = nil
    if let previous = document.kernelSessionID { retiredKernelSessionIDs.insert(previous) }
    document.kernelSessionID = nil
    widgetValueStore.clear()
    variables = []
    sessionState = .restarting
    for index in document.cells.indices {
      document.cells[index].runtime = CellRuntimeState()
    }
    scheduleSessionResolution()

    do {
      try await backend.restartSession(
        notebookURI: document.notebookURI,
        executable: details.executableURL.path,
        workingDirectory: workingDirectory.path,
        createIfMissing: createIfMissing || needsSessionCreation
      )
    } catch {
      sessionResolutionTask?.cancel()
      sessionResolutionTask = nil
      sessionState = .failed(String(describing: error))
      synchronizationError = String(describing: error)
    }
  }

  public func submitStdin(cellID: UUID, text: String) async {
    guard let sessionID = document.kernelSessionID,
      let index = document.cells.firstIndex(where: { $0.runtimeID == cellID }),
      document.cells[index].runtime.stdinPrompt?.submitted == false
    else { return }

    document.cells[index].runtime.stdinPrompt?.submitted = true
    do {
      try await backend.sendStdin(
        notebookURI: document.notebookURI,
        kernelSessionID: sessionID,
        text: text
      )
    } catch {
      synchronizationError = String(describing: error)
    }
  }

  func handleBackendDisconnected() {
    clearRuntimePackageAlert()
    backendStatus = .unavailable
    completionRefreshTask?.cancel()
    completionRefreshTask = nil
    interruptTimeoutTask?.cancel()
    interruptTimeoutTask = nil
    sessionResolutionTask?.cancel()
    sessionResolutionTask = nil
    forceRestartAvailable = false
    runAwaitingCompletion = false
    document.kernelSessionID = nil
    widgetValueStore.clear()
    variables = []
    sessionState = .failed("Backend disconnected.")
    presentError(
      code: .lspProtocol,
      cause: "The backend connection closed unexpectedly. The editor buffer is intact.",
      target: document.notebookURI,
      recoveryActions: ["Restart Backend", "Open Logs"]
    )
    for index in document.cells.indices {
      document.cells[index].runtime.status = .idle
      document.cells[index].runtime.stale = true
      document.cells[index].runtime.widgetIDs = []
      document.cells[index].runtime.stdinPrompt = nil
    }
  }

  func handleBackendRestarted() {
    backendStatus = .ready
    backendRecoveryStopped = false
    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        try await self.synchronizeOpenDocument()
        await self.reattachSessionIfAvailable()
        self.synchronizationError = nil
      } catch {
        self.synchronizationError = String(describing: error)
      }
    }
  }

  func handleAutomaticRestartStopped(stderr: [String]) {
    backendStatus = .unavailable
    backendRecoveryStopped = true
    backendLogs = stderr
    sessionState = .failed("Backend restart limit reached.")
  }
}
