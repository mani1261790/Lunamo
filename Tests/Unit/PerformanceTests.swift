import AppKit
import Foundation
import MarimoApplication
import MarimoBackend
import MarimoDomain
import MarimoEnvironment
import Testing

@testable import MarimoEditor

private actor PerformanceBackend: MarimoBackend {
  private var ready = false
  private var executionCount = 0

  func status() -> BackendStatus { ready ? .ready : .unavailable }
  func start() { ready = true }
  func parseNotebook(source _: String) -> NotebookParseOutcome { .convertible }
  func execute(
    notebookURI _: String,
    executable _: String,
    workingDirectory _: String,
    cells _: [NotebookExecutionCell]
  ) {
    executionCount += 1
  }
  func shutdown() { ready = false }
  func executions() -> Int { executionCount }
}

@Suite("Performance budgets", .serialized)
struct PerformanceTests {
  @Test("A 500-line edit reaches TextKit glyph layout within 16 ms p95")
  @MainActor
  func typingToGlyphP95() {
    let container = CodeEditorContainerView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let source = (0..<500).map { "value_\($0) = \($0)" }.joined(separator: "\n")
    container.textView.string = source
    _ = container.measuredContentHeight

    var samples: [Double] = []
    for _ in 0..<100 {
      container.textView.setSelectedRange(
        NSRange(location: container.textView.string.utf16.count, length: 0)
      )
      let start = ContinuousClock.now
      container.textView.insertText(
        " ", replacementRange: NSRange(location: NSNotFound, length: 0)
      )
      _ = container.measuredContentHeight
      samples.append(milliseconds(start.duration(to: .now)))
    }

    let measuredP95 = p95(samples)
    print("MN-PERF-003 typing-to-glyph p95=\(measuredP95)ms samples=\(samples.count)")
    #expect(measuredP95 <= 16)
  }

  @Test("A 100-cell Run All reaches backend execute within 100 ms p95")
  @MainActor
  func runDispatchP95() async {
    let executableURL = URL(fileURLWithPath: "/bin/sh")
    let workingDirectory = canonicalURL(FileManager.default.temporaryDirectory)
    let (preflight, _) = successfulPreflight(executableURL: executableURL)
    let backend = PerformanceBackend()
    let cells = (0..<100).map { NotebookCellState(code: "value_\($0) = \($0)") }
    let store = NotebookStore(
      backend: backend,
      document: NotebookDocumentState(
        sourceURL: workingDirectory.appending(path: "performance.py"),
        cells: cells,
        kernelSessionID: "performance-session"
      ),
      environmentPreflight: preflight
    )
    await store.startBackend()
    await store.choosePythonExecutable(executableURL)
    store.chooseWorkingDirectory(workingDirectory)

    var samples: [Double] = []
    for _ in 0..<30 {
      store.authorizeRunOnce()
      let start = ContinuousClock.now
      await store.send(
        .runAll(
          executable: normalizedExecutableURL(executableURL).path,
          workingDirectory: workingDirectory.path
        )
      )
      samples.append(milliseconds(start.duration(to: .now)))
    }

    let measuredP95 = p95(samples)
    print("MN-PERF-006 run-to-write p95=\(measuredP95)ms samples=\(samples.count)")
    #expect(await backend.executions() == samples.count)
    #expect(measuredP95 <= 100)
    await store.shutdownBackend()
  }

  private func p95(_ samples: [Double]) -> Double {
    let ordered = samples.sorted()
    let index = max(0, Int(ceil(Double(ordered.count) * 0.95)) - 1)
    return ordered[index]
  }

  private func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }
}
