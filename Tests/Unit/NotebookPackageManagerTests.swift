import Foundation
import MarimoEnvironment
import MarimoProcess
import Testing

private actor PackageManagerTransport: ProcessTransport {
  private(set) var requests: [ProcessLaunchRequest] = []

  func start(_ request: ProcessLaunchRequest) -> AsyncStream<ProcessEvent> {
    requests.append(request)
    return AsyncStream { continuation in
      continuation.yield(.terminated(0))
      continuation.finish()
    }
  }

  func write(_: Data) {}
  func terminate() {}
  func processIdentifier() -> Int32? { nil }
}

@Suite("Notebook package manager")
struct NotebookPackageManagerTests {
  @Test("Package requirements are deliberately narrow")
  func validatesRequirements() throws {
    #expect(try UVNotebookPackageManager.validateRequirement("keras") == "keras")
    #expect(try UVNotebookPackageManager.validateRequirement("pandas==2.3") == "pandas==2.3")
    #expect(throws: NotebookPackageManagerError.invalidRequirement("--system")) {
      try UVNotebookPackageManager.validateRequirement("--system")
    }
    #expect(throws: NotebookPackageManagerError.invalidRequirement("keras; echo unsafe")) {
      try UVNotebookPackageManager.validateRequirement("keras; echo unsafe")
    }
  }

  @Test("Install targets the exact notebook Python without a shell")
  func installsIntoExactEnvironment() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "marimonative-packages-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let uv = directory.appending(path: "uv")
    try Data("#!/bin/sh\n".utf8).write(to: uv)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: uv.path)
    let transport = PackageManagerTransport()
    let manager = UVNotebookPackageManager(uvURL: uv, makeTransport: { transport })
    let python = directory.appending(path: ".venv/bin/python")

    try await manager.install(requirements: ["keras"], pythonURL: python, workspaceURL: directory)

    let requests = await transport.requests
    #expect(requests.count == 1)
    #expect(requests[0].executableURL == uv)
    #expect(
      requests[0].arguments == [
        "pip", "install", "--python", python.path, "--no-python-downloads", "--no-progress",
        "keras",
      ])
    #expect(requests[0].currentDirectoryURL == directory)
    #expect(requests[0].environment["UV_NO_CONFIG"] == "1")
  }

  @Test("Environment creation uses the explicit app-managed destination")
  func createsEnvironmentAtManagedDestination() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "marimonative-managed-environment-\(UUID().uuidString)",
      directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let uv = directory.appending(path: "uv")
    try Data("#!/bin/sh\n".utf8).write(to: uv)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: uv.path)
    let transport = PackageManagerTransport()
    let cache = directory.appending(path: "cache")
    let manager = UVNotebookPackageManager(
      uvURL: uv, cacheURL: cache, makeTransport: { transport })
    let environment = directory.appending(path: "support/shared-v1")

    do {
      _ = try await manager.createEnvironment(
        at: environment,
        basePythonURL: URL(fileURLWithPath: "/usr/bin/python3"),
        workingDirectoryURL: directory
      )
      Issue.record("The mock transport does not create the expected Python executable")
    } catch let error as NotebookPackageManagerError {
      guard case .processFailed(status: -1, _) = error else {
        Issue.record("Unexpected error: \(error)")
        return
      }
    }

    let requests = await transport.requests
    #expect(requests.count == 1)
    #expect(requests[0].arguments.last == environment.path)
    #expect(requests[0].currentDirectoryURL == directory)
    #expect(requests[0].environment["UV_CACHE_DIR"] == cache.path)
  }
}

@Suite("Managed Python environment storage")
struct ManagedPythonEnvironmentStoreTests {
  @Test("Shared is the default and project choices have stable isolated paths")
  func scopeAndPaths() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "marimonative-environment-registry-\(UUID().uuidString)",
      directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ManagedPythonEnvironmentStore(applicationSupportDirectory: directory)
    let workspace = URL(fileURLWithPath: "/tmp/example-project", isDirectory: true)
    let otherWorkspace = URL(fileURLWithPath: "/tmp/other-project", isDirectory: true)

    #expect(await store.scope(for: workspace) == .shared)
    let shared = await store.environmentURL(for: .shared, workspaceURL: workspace)
    let project = await store.environmentURL(for: .project, workspaceURL: workspace)
    let otherShared = await store.environmentURL(for: .shared, workspaceURL: otherWorkspace)
    let otherProject = await store.environmentURL(for: .project, workspaceURL: otherWorkspace)
    #expect(shared.lastPathComponent == "shared-v1")
    #expect(shared == otherShared)
    #expect(project.path.contains("/projects/"))
    #expect(project != shared)
    #expect(project != otherProject)

    try await store.setScope(.project, for: workspace)
    #expect(await store.scope(for: workspace) == .project)
    let reopened = ManagedPythonEnvironmentStore(applicationSupportDirectory: directory)
    #expect(await reopened.scope(for: workspace) == .project)
    #expect(await reopened.scope(for: otherWorkspace) == .shared)
    try await store.setScope(.shared, for: workspace)
    #expect(await store.scope(for: workspace) == .shared)
  }
}
