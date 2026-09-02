import Foundation
import MarimoBackend
import MarimoDomain

extension NotebookStore {
  public var sessionAllowsInterrupt: Bool {
    (sessionState == .running || sessionState == .interrupting) && document.kernelSessionID != nil
  }

  public var sessionAllowsRestart: Bool {
    guard backendStatus == .ready else { return false }
    guard case .ready = environmentState else { return false }
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

    interruptTimeoutTask?.cancel()
    interruptTimeoutTask = nil
    forceRestartAvailable = false
    runAwaitingCompletion = false
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
        createIfMissing: createIfMissing
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
    backendStatus = .unavailable
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
    for index in document.cells.indices {
      document.cells[index].runtime.status = .idle
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
