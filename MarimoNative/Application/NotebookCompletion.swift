import Foundation
import MarimoDomain
import OSLog

extension NotebookStore {
  func scheduleCompletionRefresh(sessionID: String) {
    completionRefreshTask?.cancel()
    completionRefreshTask = Task { @MainActor [weak self] in
      // marimo may enqueue the last cell-op immediately after completed-run. Let the event
      // router apply that ordered tail before taking the authoritative output snapshot.
      try? await Task.sleep(for: .milliseconds(50))
      guard !Task.isCancelled, let self, self.document.kernelSessionID == sessionID else { return }
      await self.refreshRuntimeOutputs(sessionID: sessionID)
      guard !Task.isCancelled, self.document.kernelSessionID == sessionID else { return }
      let stillRunning = self.document.cells.contains {
        $0.runtime.status == .queued || $0.runtime.status == .running
      }
      self.runAwaitingCompletion = stillRunning
      if self.sessionState != .interrupting {
        self.sessionState = stillRunning ? .running : .idle
      }
      self.completionRefreshTask = nil
    }
  }

  private func refreshRuntimeOutputs(sessionID: String) async {
    let documentID = document.documentID
    let uri = document.notebookURI
    do {
      let replays = try await backend.readNotebookOutputs(notebookURI: uri)
      guard !Task.isCancelled, document.documentID == documentID,
        document.notebookURI == uri, document.kernelSessionID == sessionID
      else { return }
      for replay in replays {
        applyCellOperation(
          replay.payload,
          executedSource: replay.executedSource,
          replacingConsole: true
        )
      }
      if runtimePackageAlertSessionID == sessionID,
        !document.cells.contains(where: { $0.runtime.hasExecutionError })
      {
        clearRuntimePackageAlert()
      }
    } catch {
      MarimoLog.output.debug("Could not refresh completed-run outputs")
    }
  }

  func clearRuntimePackageAlert() {
    guard runtimePackageAlertSessionID != nil else { return }
    runtimePackageAlertSessionID = nil
    missingPackages = []
  }
}
