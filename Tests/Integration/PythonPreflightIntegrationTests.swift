import Foundation
import MarimoEnvironment
import MarimoProcess
import Testing

@Suite("Python preflight integration", .serialized)
struct PythonPreflightIntegrationTests {
  @Test("Bundled arm64 Python and marimo 0.24.0 pass the fixed preflight")
  func bundledRuntimePreflight() async throws {
    let executable = repositoryRoot().appending(path: ".build/Sidecar/bin/python3")
    let details = try await PythonPreflightService().inspect(
      PythonEnvironmentCandidate(executableURL: executable, kind: .userSelected)
    )

    #expect(details.executableURL == normalizedExecutableURL(executable))
    #expect(details.realExecutableURL == canonicalURL(executable))
    #expect(details.pythonVersion.major == 3)
    #expect((10...14).contains(details.pythonVersion.minor))
    #expect(details.architecture == "arm64")
    #expect(details.marimoVersion == "0.24.0")
  }

  @Test("A virtual-environment symlink is launched without replacing it by its real path")
  func virtualEnvironmentLaunchPath() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "marimonative-preflight-venv-\(UUID().uuidString)", directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let bin = root.appending(path: "bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    let bundled = repositoryRoot().appending(path: ".build/Sidecar/bin/python3")
    let selected = bin.appending(path: "python")
    try FileManager.default.createSymbolicLink(at: selected, withDestinationURL: bundled)
    let sidecarBin = canonicalURL(bundled).deletingLastPathComponent()
    try Data(
      """
      home = \(sidecarBin.path)
      include-system-site-packages = true
      version = 3.13.15
      """.utf8
    ).write(to: root.appending(path: "pyvenv.cfg"))

    let details = try await PythonPreflightService().inspect(
      PythonEnvironmentCandidate(executableURL: selected, kind: .notebookVirtualEnvironment)
    )

    #expect(details.executableURL == normalizedExecutableURL(selected))
    #expect(details.realExecutableURL == canonicalURL(bundled))
    #expect(details.marimoVersion == "0.24.0")
  }

  @Test("A timed-out preflight that ignores TERM is force-killed")
  func timeoutForceKillsProcess() async throws {
    let script = FileManager.default.temporaryDirectory.appending(
      path: "marimonative-hanging-preflight-\(UUID().uuidString)"
    )
    defer { try? FileManager.default.removeItem(at: script) }
    try Data("#!/bin/sh\ntrap '' TERM\nwhile :; do sleep 1; done\n".utf8).write(to: script)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    let transport = LSPProcess()
    let service = PythonPreflightService(
      timeout: .milliseconds(50), makeTransport: { transport }
    )

    await #expect(throws: PythonPreflightFailure.timedOut) {
      try await service.inspect(
        PythonEnvironmentCandidate(executableURL: script, kind: .userSelected)
      )
    }
    for _ in 0..<20 {
      if await transport.processIdentifier() == nil { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await transport.processIdentifier() == nil)
  }

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
