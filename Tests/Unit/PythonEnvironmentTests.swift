import Foundation
import MarimoEnvironment
import MarimoProcess
import Testing

@Suite("Python environment", .serialized)
struct PythonEnvironmentTests {
  @Test("Candidates follow notebook, workspace, and saved-selection order")
  func candidateOrder() async throws {
    try await withEnvironmentDirectory { directory in
      let workspace = directory.appending(path: "workspace")
      let notebookDirectory = workspace.appending(path: "examples")
      try FileManager.default.createDirectory(
        at: workspace.appending(path: ".git"), withIntermediateDirectories: true
      )
      try FileManager.default.createDirectory(
        at: notebookDirectory, withIntermediateDirectories: true)
      let notebookPython = notebookDirectory.appending(path: ".venv/bin/python")
      let workspacePython = workspace.appending(path: ".venv/bin/python")
      let savedPython = directory.appending(path: "saved-python")
      try makeExecutable(notebookPython)
      try makeExecutable(workspacePython)
      try makeExecutable(savedPython)
      let support = directory.appending(path: "support")
      let selectionStore = WorkspaceEnvironmentStore(applicationSupportDirectory: support)
      let discovery = PythonEnvironmentDiscovery(store: selectionStore)
      let savedIdentity = try executableIdentity(at: savedPython)
      try await selectionStore.save(
        SavedEnvironmentSelection(executableURL: savedPython, identity: savedIdentity),
        for: workspace
      )
      let persisted = try JSONDecoder().decode(
        [String: SavedEnvironmentSelection].self,
        from: Data(contentsOf: support.appending(path: "workspace-environments.json"))
      )
      #expect(Array(persisted.keys) == [canonicalURL(workspace).path])

      let candidates = await discovery.candidates(for: notebookDirectory.appending(path: "demo.py"))
      #expect(
        candidates.map(\.kind) == [
          .notebookVirtualEnvironment, .workspaceVirtualEnvironment, .savedWorkspaceSelection,
        ])
      #expect(
        candidates.map { canonicalURL($0.executableURL) } == [
          canonicalURL(notebookPython), canonicalURL(workspacePython), canonicalURL(savedPython),
        ])
      #expect(
        candidates.map(\.executableURL) == [
          normalizedExecutableURL(notebookPython),
          normalizedExecutableURL(workspacePython),
          normalizedExecutableURL(savedPython),
        ])
    }
  }

  @Test("A changed saved executable is not reused")
  func changedSavedExecutable() async throws {
    try await withEnvironmentDirectory { directory in
      let workspace = directory.appending(path: "workspace")
      try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
      let executable = directory.appending(path: "python")
      try makeExecutable(executable, contents: "first")
      let support = directory.appending(path: "support")
      let store = WorkspaceEnvironmentStore(applicationSupportDirectory: support)
      try await store.save(
        SavedEnvironmentSelection(
          executableURL: executable,
          identity: try executableIdentity(at: executable)
        ),
        for: workspace
      )
      try makeExecutable(executable, contents: "changed executable contents")

      let candidates = await PythonEnvironmentDiscovery(store: store).candidates(
        for: workspace.appending(path: "demo.py")
      )
      #expect(candidates.isEmpty)
    }
  }

  @Test("Preflight launches the selected executable directly with the fixed script")
  func directPreflight() async throws {
    let executable = URL(fileURLWithPath: "/bin/sh")
    let (service, transport) = successfulPreflight(executableURL: executable)
    let details = try await service.inspect(
      PythonEnvironmentCandidate(executableURL: executable, kind: .userSelected)
    )

    #expect(details.executableURL == normalizedExecutableURL(executable))
    #expect(details.realExecutableURL == canonicalURL(executable))
    #expect(details.pythonVersion == PythonVersion(major: 3, minor: 13, patch: 1))
    #expect(details.marimoVersion == "0.24.0")
    let requests = await transport.recordedRequests()
    #expect(requests.count == 1)
    #expect(requests[0].executableURL == normalizedExecutableURL(executable))
    #expect(requests[0].arguments == ["-I", "-c", PythonPreflightService.fixedScript])
    #expect(requests[0].environment["PYTHONNOUSERSITE"] == "1")
  }

  @Test("Unsupported Python, architecture, and marimo versions are rejected")
  func compatibilityBounds() async {
    let executable = URL(fileURLWithPath: "/bin/sh")
    let (oldPython, _) = successfulPreflight(executableURL: executable, python: [3, 9, 20])
    await #expect(
      throws: PythonPreflightFailure.unsupportedPython(.init(major: 3, minor: 9, patch: 20))
    ) {
      try await oldPython.inspect(.init(executableURL: executable, kind: .userSelected))
    }
    let (futurePython, _) = successfulPreflight(executableURL: executable, python: [3, 15, 0])
    await #expect(
      throws: PythonPreflightFailure.unsupportedPython(.init(major: 3, minor: 15, patch: 0))
    ) {
      try await futurePython.inspect(.init(executableURL: executable, kind: .userSelected))
    }
    let (wrongArchitecture, _) = successfulPreflight(
      executableURL: executable, architecture: "x86_64")
    await #expect(throws: PythonPreflightFailure.unsupportedArchitecture("x86_64")) {
      try await wrongArchitecture.inspect(.init(executableURL: executable, kind: .userSelected))
    }
    let (wrongMarimo, _) = successfulPreflight(executableURL: executable, marimoVersion: "0.23.3")
    await #expect(throws: PythonPreflightFailure.unsupportedMarimo("0.23.3")) {
      try await wrongMarimo.inspect(.init(executableURL: executable, kind: .userSelected))
    }
  }

  @Test("Preflight enforces stdout, stderr, and timeout bounds")
  func resourceBounds() async {
    let executable = URL(fileURLWithPath: "/bin/sh")
    let candidate = PythonEnvironmentCandidate(executableURL: executable, kind: .userSelected)
    let stdoutTransport = PreflightMockTransport(events: [
      .stdout(Data(repeating: 0x78, count: PythonPreflightService.outputLimit + 1))
    ])
    let stdoutService = PythonPreflightService(makeTransport: { stdoutTransport })
    await #expect(throws: PythonPreflightFailure.stdoutLimitExceeded) {
      try await stdoutService.inspect(candidate)
    }
    let stderrTransport = PreflightMockTransport(events: [
      .stderr(Data(repeating: 0x78, count: PythonPreflightService.outputLimit + 1))
    ])
    let stderrService = PythonPreflightService(makeTransport: { stderrTransport })
    await #expect(throws: PythonPreflightFailure.stderrLimitExceeded) {
      try await stderrService.inspect(candidate)
    }
    let hangingTransport = PreflightMockTransport(events: [], finishes: false)
    let timeoutService = PythonPreflightService(
      timeout: .milliseconds(10), makeTransport: { hangingTransport }
    )
    await #expect(throws: PythonPreflightFailure.timedOut) {
      try await timeoutService.inspect(candidate)
    }
    #expect(await hangingTransport.wasTerminated())
  }

  private func makeExecutable(_ url: URL, contents: String = "#!/bin/sh\n") throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data(contents.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
  }

  private func withEnvironmentDirectory(
    _ operation: (URL) async throws -> Void
  ) async throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "marimonative-environment-\(UUID().uuidString)", directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await operation(directory)
  }
}
