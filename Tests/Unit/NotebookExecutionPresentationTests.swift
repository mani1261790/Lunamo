import MarimoDomain
import Testing

@testable import MarimoUI

@Suite("Notebook execution presentation")
struct NotebookExecutionPresentationTests {
  @Test("Interrupted and failed runs never appear complete or retain a busy badge")
  @MainActor
  func transitions() {
    var cell = NotebookCellState(code: "1")
    cell.runtime.lastExecutedCode = "1"
    #expect(NotebookExecutionPresentation(session: .running, cells: [cell]).isBusy)
    let stopping = NotebookExecutionPresentation(session: .interrupting, cells: [cell])
    #expect(stopping.phase == .stopping)
    #expect(stopping.dockBadge != nil)
    #expect(NotebookExecutionPresentation(session: .idle, cells: [cell]).phase == .complete)
    cell.runtime.status = .error
    let failure = NotebookExecutionPresentation(session: .idle, cells: [cell])
    #expect(failure.phase == .needsAttention)
    #expect(failure.completed == 0)
    #expect(failure.dockBadge == nil)
    cell.runtime.output = MarimoOutput(
      channel: .marimoError, mimeType: "application/vnd.marimo+error",
      data: .array([.object(["type": .string("interruption")])]))
    #expect(cell.runtime.wasInterrupted)
    let interrupted = NotebookExecutionPresentation(session: .idle, cells: [cell])
    #expect(interrupted.phase == .stopped)
    #expect(interrupted.dockBadge == nil)
    #expect(interrupted.completed == 0)
    #expect(NotebookExecutionPresentation(session: .failed("test"), cells: [cell]).phase == .failed)
  }

  @Test("Edited, stale, queued and disabled cells cannot invent completion")
  @MainActor
  func freshness() {
    var cell = NotebookCellState(code: "2")
    cell.runtime.lastExecutedCode = "1"
    #expect(NotebookExecutionPresentation(session: .idle, cells: [cell]).phase == .ready)
    cell.runtime.lastExecutedCode = "2"
    cell.runtime.stale = true
    #expect(NotebookExecutionPresentation(session: .idle, cells: [cell]).completed == 0)
    cell.runtime.status = .queued
    #expect(NotebookExecutionPresentation(session: .idle, cells: [cell]).phase == .running)
    cell.configuration.disabled = true
    let disabled = NotebookExecutionPresentation(session: .idle, cells: [cell])
    #expect(disabled.total == 0)
    #expect(disabled.phase == .ready)
    #expect(NotebookExecutionPresentation(session: .closed, cells: [cell]).dockBadge == nil)
  }
}
