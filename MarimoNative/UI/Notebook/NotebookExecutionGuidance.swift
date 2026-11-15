import MarimoApplication
import MarimoDomain
import SwiftUI

@MainActor
func notebookRunDisabledHelp(store: NotebookStore) -> String {
  if !store.documentAllowsExecution {
    return localizedUI("This notebook cannot run in its current state")
  }
  if store.backendStatus != .ready {
    return localizedUI("The Python backend is not ready")
  }
  switch store.environmentState {
  case .notConfigured:
    return localizedUI("Choose a Python environment to run")
  case .checking:
    return localizedUI("Python is still being checked")
  case .invalid:
    return localizedUI("The selected Python environment cannot run this notebook")
  case .needsWorkingDirectory:
    return localizedUI("Choose a working folder before running this untitled notebook")
  case .selected:
    return localizedUI("Run once to check the selected Python environment")
  case .ready:
    return localizedUI("The kernel is not ready to run another cell")
  }
}

func statusLabel(_ status: ExecutionStatus) -> String {
  switch status {
  case .idle: localizedUI("Idle")
  case .queued: localizedUI("Queued")
  case .running: localizedUI("Running")
  case .error: localizedUI("Error")
  case .disabledTransitively: localizedUI("Disabled")
  }
}

extension View {
  func executionSetupBannerStyle() -> some View {
    padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

extension NotebookRootView {
  var documentTitle: String {
    store.document.sourceURL?.lastPathComponent ?? localizedUI("Untitled")
  }

  var canRun: Bool {
    store.environmentAllowsExecutionRequest && store.backendStatus == .ready
      && store.sessionAllowsRun && store.documentAllowsExecution
  }

  var runDisabledHelp: String {
    notebookRunDisabledHelp(store: store)
  }
}
