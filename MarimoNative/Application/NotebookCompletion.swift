import Foundation
import OSLog

extension NotebookStore {
  func scheduleCompletionRefresh(sessionID: String) {
    completionRefreshTask?.cancel()
    completionRefreshTask = Task { @MainActor [weak self] in
      // marimo may enqueue the last cell-op immediately after completed-run. Let the event
      // router apply that ordered tail before taking the authoritative output snapshot.
      try? await Task.sleep(for: .milliseconds(50))
      guard !Task.isCancelled, let self, self.document.kernelSessionID == sessionID else { return }
      await self.refreshRuntimeOutputs()
      guard !Task.isCancelled, self.document.kernelSessionID == sessionID else { return }
      self.sessionState = .idle
      self.completionRefreshTask = nil
    }
  }

  private func refreshRuntimeOutputs() async {
    do {
      for replay in try await backend.readNotebookOutputs(notebookURI: document.notebookURI) {
        applyCellOperation(
          replay.payload,
          executedSource: replay.executedSource,
          replacingConsole: true
        )
      }
    } catch {
      NotebookCompletionLog.logger.debug("Could not refresh completed-run outputs")
    }
  }
}

private enum NotebookCompletionLog {
  static let logger = Logger(subsystem: "MarimoNative", category: "NotebookCompletion")
}
