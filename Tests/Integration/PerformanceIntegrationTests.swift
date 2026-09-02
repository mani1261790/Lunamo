import Foundation
import MarimoApplication
import MarimoBackend
import MarimoDomain
import MarimoEnvironment
import Testing

extension BundledSidecarIntegrationTests {
  @Test("A warm sidecar opens a 100-cell 1 MiB notebook within one second p95")
  @MainActor
  func warmOpenP95() async throws {
    let root = performanceRepositoryRoot()
    let sidecar = root.appending(path: ".build/Sidecar")
    guard FileManager.default.isExecutableFile(atPath: sidecar.appending(path: "bin/python").path)
    else {
      Issue.record("Build .build/Sidecar before running performance integration tests")
      return
    }
    let support = FileManager.default.temporaryDirectory.appending(
      path: "marimonative-performance-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: support) }
    let notebook = support.appending(path: "one-mebibyte-100-cells.py")
    let source = performanceNotebookSource()
    #expect(Data(source.utf8).count >= 1_048_576)
    try Data(source.utf8).write(to: notebook)

    let adapter = try MarimoLSPAdapter(sidecarDirectory: sidecar)
    let store = NotebookStore(
      backend: adapter,
      folderTrustStore: FolderTrustStore(applicationSupportDirectory: support),
      recentDocumentStore: RecentDocumentStore(fileURL: support.appending(path: "recent.json"))
    )
    await store.startBackend()
    await store.open(notebook)
    #expect(store.document.cells.count == 100)

    var samples: [Double] = []
    for _ in 0..<20 {
      let start = ContinuousClock.now
      await store.open(notebook)
      samples.append(performanceMilliseconds(start.duration(to: .now)))
      #expect(store.document.cells.count == 100)
    }
    let ordered = samples.sorted()
    let measuredP95 = ordered[max(0, Int(ceil(Double(ordered.count) * 0.95)) - 1)]
    print("MN-PERF-001 warm-open p95=\(measuredP95)ms samples=\(samples.count)")
    #expect(measuredP95 <= 1_000)
    await store.shutdownBackend()
  }
}

private func performanceNotebookSource() -> String {
  let padding = String(repeating: "x", count: 10_420)
  let cells = (0..<100).map { index in
    """


    @app.cell
    def _():
        # \(padding)
        value_\(index) = \(index)
        return (value_\(index),)
    """
  }.joined()
  return """
    import marimo

    __generated_with = "0.24.0"
    app = marimo.App()
    \(cells)


    if __name__ == "__main__":
        app.run()
    """
}

private func performanceMilliseconds(_ duration: Duration) -> Double {
  let components = duration.components
  return Double(components.seconds) * 1_000
    + Double(components.attoseconds) / 1_000_000_000_000_000
}

private func performanceRepositoryRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}
