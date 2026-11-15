import AppKit
import MarimoDomain
import SwiftUI

struct NotebookExecutionPresentation: Equatable {
  enum Phase: Equatable {
    case ready, starting, running, stopping, restarting, failed, needsAttention, stopped, complete
  }

  let phase: Phase
  let completed: Int
  let total: Int

  init(session: NotebookSessionState, cells: [NotebookCellState]) {
    let enabled = cells.filter { !$0.configuration.disabled }
    completed = enabled.filter { $0.runtime.successfullyExecuted($0.code) }.count
    total = enabled.count
    switch session {
    case .starting: phase = .starting
    case .interrupting: phase = .stopping
    case .restarting: phase = .restarting
    case .failed: phase = .failed
    case .running: phase = .running
    case .notStarted, .closed: phase = .ready
    case .idle:
      if enabled.contains(where: { $0.runtime.status == .running || $0.runtime.status == .queued })
      {
        phase = .running
      } else if enabled.contains(where: {
        ($0.runtime.hasExecutionError && !$0.runtime.wasInterrupted)
          || $0.runtime.status == .disabledTransitively
      }) {
        phase = .needsAttention
      } else if enabled.contains(where: { $0.runtime.wasInterrupted }) {
        phase = .stopped
      } else {
        phase = total > 0 && completed == total ? .complete : .ready
      }
    }
  }

  var titleKey: String {
    switch phase {
    case .ready: "Ready"
    case .starting: "Starting…"
    case .running: "Running"
    case .stopping: "Stopping…"
    case .restarting: "Restarting…"
    case .failed: "Execution Failed"
    case .needsAttention: "Check Cell Results"
    case .complete: "All Cells Up to Date"
    case .stopped: "Execution Stopped"
    }
  }

  var isBusy: Bool {
    [.starting, .running, .stopping, .restarting].contains(phase)
  }

  var symbol: String {
    switch phase {
    case .failed, .needsAttention: "exclamationmark.triangle"
    case .complete: "checkmark.circle"
    case .stopped: "stop.circle"
    default: "circle"
    }
  }

  // A badge reports a state, never an invented fraction of execution time.
  var dockBadge: String? { isBusy ? localizedUI(titleKey) : nil }
}

extension NotebookRootView {
  var executionPresentation: NotebookExecutionPresentation {
    NotebookExecutionPresentation(session: store.sessionState, cells: store.document.cells)
  }

  var executionSummary: some View {
    let state = executionPresentation
    return HStack(spacing: 5) {
      if state.isBusy {
        ProgressView().controlSize(.small)
      } else {
        Image(systemName: state.symbol)
      }
      Text(localizedUI(state.titleKey))
        .lineLimit(1)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .help(localizedUI("Cells up to date: %d of %d", state.completed, state.total))
    .accessibilityElement(children: .combine)
    .accessibilityValue(localizedUI("Cells up to date: %d of %d", state.completed, state.total))
  }
}
