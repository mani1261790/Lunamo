import Foundation
import MarimoBackend
import MarimoProcess
import Testing

@Suite("Bundled sidecar", .serialized)
struct BundledSidecarIntegrationTests {
  @Test("Initialize and bounded shutdown leave no sidecar process")
  func initializeAndShutdown() async throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let sidecar = root.appending(path: ".build/Sidecar")
    guard FileManager.default.fileExists(atPath: sidecar.path) else {
      Issue.record("Build .build/Sidecar before running integration tests")
      return
    }
    let process = LSPProcess()
    let connection = JSONRPCConnection(transport: process)
    _ = try await connection.startAndInitialize(
      request: SidecarLaunchRequest.make(sidecarDirectory: sidecar)
    )
    #expect(await connection.currentState() == .ready)
    await connection.shutdown()
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    while await process.processIdentifier() != nil, clock.now < deadline {
      try await Task.sleep(for: .milliseconds(25))
    }
    #expect(await process.processIdentifier() == nil)
    #expect(await connection.pendingRequestCount() == 0)
  }

  @Test("Real adapter distinguishes two-cell, invalid, and convertible sources")
  func parseOutcomes() async throws {
    let root = repositoryRoot()
    let sidecar = root.appending(path: ".build/Sidecar")
    guard FileManager.default.fileExists(atPath: sidecar.path) else {
      Issue.record("Build .build/Sidecar before running integration tests")
      return
    }
    let adapter = try MarimoLSPAdapter(sidecarDirectory: sidecar)
    try await adapter.start()
    let source = try String(
      contentsOf: root.appending(path: "Tests/Fixtures/two_cell_notebook.py"),
      encoding: .utf8
    )
    let parsed = try await adapter.parseNotebook(source: source)
    guard case .success(let notebook) = parsed else {
      Issue.record("Two-cell fixture did not parse successfully")
      await adapter.shutdown()
      return
    }
    #expect(notebook.cells.count == 2)
    #expect(notebook.cells[0].code.contains("first = 20"))
    #expect(notebook.cells[1].code.contains("second = first + 22"))
    #expect(
      try await adapter.parseNotebook(source: "def broken(:\n")
        == .invalidSyntax(line: 1, column: 12)
    )
    #expect(try await adapter.parseNotebook(source: "print('hello')\n") == .convertible)
    await adapter.shutdown()
  }

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
