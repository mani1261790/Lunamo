import Foundation
import MarimoProcess

public enum NotebookPackageOperationState: Sendable, Equatable {
  case idle
  case preparingEnvironment
  case installing([String])
  case succeeded([String])
  case failed(String)

  public var isRunning: Bool {
    switch self {
    case .preparingEnvironment, .installing: true
    case .idle, .succeeded, .failed: false
    }
  }
}

public enum NotebookPackageManagerError: LocalizedError, Sendable, Equatable {
  case unavailable
  case invalidRequirement(String)
  case workspaceUnavailable(URL)
  case environmentDirectoryOccupied(URL)
  case processFailed(status: Int32, message: String)
  case outputLimitExceeded

  public var errorDescription: String? {
    switch self {
    case .unavailable:
      "The built-in package manager is unavailable."
    case .invalidRequirement(let requirement):
      "The package name is invalid: \(requirement)"
    case .workspaceUnavailable(let url):
      "The notebook folder is unavailable: \(url.path)"
    case .environmentDirectoryOccupied(let url):
      "A non-Python folder already exists at \(url.path)."
    case .processFailed(_, let message):
      message
    case .outputLimitExceeded:
      "Package manager output exceeded the safety limit."
    }
  }
}

public protocol NotebookPackageManaging: Sendable {
  func createEnvironment(
    at environmentURL: URL,
    basePythonURL: URL,
    workingDirectoryURL: URL
  ) async throws -> URL
  func install(requirements: [String], pythonURL: URL, workspaceURL: URL) async throws
}

public actor UVNotebookPackageManager: NotebookPackageManaging {
  public static let maximumOutputBytes = 1_048_576

  private let uvURL: URL
  private let cacheURL: URL
  private let makeTransport: @Sendable () -> any ProcessTransport

  public init(
    uvURL: URL,
    cacheURL: URL = ManagedPythonEnvironmentStore().uvCacheURL,
    makeTransport: @escaping @Sendable () -> any ProcessTransport = { LSPProcess() }
  ) {
    self.uvURL = uvURL.standardizedFileURL
    self.cacheURL = cacheURL.standardizedFileURL
    self.makeTransport = makeTransport
  }

  public func createEnvironment(
    at environmentURL: URL,
    basePythonURL: URL,
    workingDirectoryURL: URL
  ) async throws -> URL {
    guard FileManager.default.isExecutableFile(atPath: uvURL.path) else {
      throw NotebookPackageManagerError.unavailable
    }
    var isDirectory: ObjCBool = false
    guard workingDirectoryURL.isFileURL,
      FileManager.default.fileExists(atPath: workingDirectoryURL.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { throw NotebookPackageManagerError.workspaceUnavailable(workingDirectoryURL) }

    let pythonURL = environmentURL.appending(path: "bin/python")
    if FileManager.default.isExecutableFile(atPath: pythonURL.path) { return pythonURL }
    if FileManager.default.fileExists(atPath: environmentURL.path) {
      throw NotebookPackageManagerError.environmentDirectoryOccupied(environmentURL)
    }

    try FileManager.default.createDirectory(
      at: environmentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try await run(
      arguments: [
        "venv", "--no-project", "--no-python-downloads", "--seed", "--system-site-packages",
        "--python", basePythonURL.path, environmentURL.path,
      ],
      in: workingDirectoryURL
    )
    guard FileManager.default.isExecutableFile(atPath: pythonURL.path) else {
      throw NotebookPackageManagerError.processFailed(
        status: -1, message: "The notebook environment was not created correctly.")
    }
    return pythonURL
  }

  public func install(requirements: [String], pythonURL: URL, workspaceURL: URL) async throws {
    let normalized = try requirements.map(Self.validateRequirement)
    guard !normalized.isEmpty else { return }
    try await run(
      arguments: [
        "pip", "install", "--python", pythonURL.path, "--no-python-downloads", "--no-progress",
      ] + normalized,
      in: workspaceURL
    )
  }

  public static func validateRequirement(_ rawValue: String) throws -> String {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value.utf8.count <= 200, value.first != "-",
      value.range(
        of:
          #"^[A-Za-z0-9][A-Za-z0-9._-]*(?:\[[A-Za-z0-9,._-]+\])?(?:(?:==|!=|<=|>=|~=|<|>)[A-Za-z0-9.*+!_-]+)?$"#,
        options: .regularExpression) != nil
    else { throw NotebookPackageManagerError.invalidRequirement(rawValue) }
    return value
  }

  private func run(arguments: [String], in directoryURL: URL) async throws {
    let transport = makeTransport()
    let stream = try await transport.start(
      ProcessLaunchRequest(
        executableURL: uvURL,
        arguments: arguments,
        environment: [
          "LANG": "en_US.UTF-8",
          "PATH": "/usr/bin:/bin",
          "UV_NO_CONFIG": "1",
          "UV_NO_PROGRESS": "1",
          "UV_PYTHON_DOWNLOADS": "never",
          "UV_CACHE_DIR": cacheURL.path,
        ],
        currentDirectoryURL: directoryURL
      )
    )
    var output = Data()
    var terminationStatus: Int32?
    for await event in stream {
      switch event {
      case .stdout(let data), .stderr(let data):
        guard output.count + data.count <= Self.maximumOutputBytes else {
          await transport.forceTerminate()
          throw NotebookPackageManagerError.outputLimitExceeded
        }
        output.append(data)
      case .terminated(let status):
        terminationStatus = status
        guard status == 0 else {
          let message = String(decoding: output, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
          throw NotebookPackageManagerError.processFailed(
            status: status,
            message: message.isEmpty ? "Package manager exited with status \(status)." : message
          )
        }
      }
    }
    guard terminationStatus != nil else {
      throw NotebookPackageManagerError.processFailed(
        status: -1, message: "Package manager ended without a status.")
    }
  }
}
