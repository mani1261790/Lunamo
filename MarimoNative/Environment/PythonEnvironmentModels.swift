import Foundation

public struct PythonVersion: Codable, Sendable, Equatable, Comparable, CustomStringConvertible {
  public let major: Int
  public let minor: Int
  public let patch: Int

  public init(major: Int, minor: Int, patch: Int) {
    self.major = major
    self.minor = minor
    self.patch = patch
  }

  public var description: String { "\(major).\(minor).\(patch)" }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
  }
}

public enum PythonEnvironmentKind: String, Codable, Sendable, Equatable {
  case notebookVirtualEnvironment
  case workspaceVirtualEnvironment
  case savedWorkspaceSelection
  case userSelected

  public var displayName: String {
    switch self {
    case .notebookVirtualEnvironment: "Notebook .venv"
    case .workspaceVirtualEnvironment: "Workspace .venv"
    case .savedWorkspaceSelection: "Saved workspace selection"
    case .userSelected: "User selected"
    }
  }
}

public struct ExecutableIdentity: Codable, Sendable, Equatable {
  public let canonicalPath: String
  public let volumeIdentifier: UInt64
  public let fileIdentifier: UInt64
  public let modificationSeconds: Int64
  public let modificationNanoseconds: Int64
  public let size: Int64
  public let contentSHA256: String

  public init(
    canonicalPath: String,
    volumeIdentifier: UInt64,
    fileIdentifier: UInt64,
    modificationSeconds: Int64,
    modificationNanoseconds: Int64,
    size: Int64,
    contentSHA256: String
  ) {
    self.canonicalPath = canonicalPath
    self.volumeIdentifier = volumeIdentifier
    self.fileIdentifier = fileIdentifier
    self.modificationSeconds = modificationSeconds
    self.modificationNanoseconds = modificationNanoseconds
    self.size = size
    self.contentSHA256 = contentSHA256
  }
}

public struct PythonEnvironmentCandidate: Codable, Sendable, Equatable, Identifiable {
  public let executableURL: URL
  public let kind: PythonEnvironmentKind
  public let expectedIdentity: ExecutableIdentity?

  public init(
    executableURL: URL,
    kind: PythonEnvironmentKind,
    expectedIdentity: ExecutableIdentity? = nil
  ) {
    self.executableURL = executableURL
    self.kind = kind
    self.expectedIdentity = expectedIdentity
  }

  public var id: String { "\(kind.rawValue):\(executableURL.path)" }
}

public struct PythonEnvironmentDetails: Sendable, Equatable {
  public let executableURL: URL
  public let realExecutableURL: URL
  public let pythonVersion: PythonVersion
  public let architecture: String
  public let marimoVersion: String
  public let marimoModuleURL: URL
  public let kind: PythonEnvironmentKind
  public let identity: ExecutableIdentity

  public init(
    executableURL: URL,
    realExecutableURL: URL,
    pythonVersion: PythonVersion,
    architecture: String,
    marimoVersion: String,
    marimoModuleURL: URL,
    kind: PythonEnvironmentKind,
    identity: ExecutableIdentity
  ) {
    self.executableURL = executableURL
    self.realExecutableURL = realExecutableURL
    self.pythonVersion = pythonVersion
    self.architecture = architecture
    self.marimoVersion = marimoVersion
    self.marimoModuleURL = marimoModuleURL
    self.kind = kind
    self.identity = identity
  }
}

public enum PythonPreflightFailure: Error, Sendable, Equatable {
  case missingExecutable(URL)
  case executableChanged(URL)
  case launchFailed(String)
  case timedOut
  case stdoutLimitExceeded
  case stderrLimitExceeded
  case nonzeroExit(Int32)
  case invalidJSON
  case executableMismatch(expected: URL, reported: URL)
  case unsupportedPython(PythonVersion)
  case unsupportedArchitecture(String)
  case unsupportedMarimo(String)

  public var userMessage: String {
    switch self {
    case .missingExecutable(let url): "Python executable is missing or not executable: \(url.path)"
    case .executableChanged(let url): "The saved Python executable changed: \(url.path)"
    case .launchFailed(let message): "Python preflight could not start: \(message)"
    case .timedOut: "Python preflight exceeded 5 seconds."
    case .stdoutLimitExceeded: "Python preflight stdout exceeded 64 KiB."
    case .stderrLimitExceeded: "Python preflight stderr exceeded 64 KiB."
    case .nonzeroExit(let status): "Python preflight exited with status \(status)."
    case .invalidJSON: "Python preflight returned invalid JSON."
    case .executableMismatch(let expected, let reported):
      "Python reported a different executable (expected \(expected.path), got \(reported.path))."
    case .unsupportedPython(let version):
      "Python \(version) is unsupported. Required: Python 3.10–3.14."
    case .unsupportedArchitecture(let architecture):
      "Python architecture \(architecture) is unsupported. Required: arm64."
    case .unsupportedMarimo(let version):
      "marimo \(version) is unsupported. Required: marimo 0.24.0."
    }
  }
}

public enum NotebookEnvironmentState: Sendable, Equatable {
  case notConfigured
  case selected(PythonEnvironmentCandidate, workingDirectory: URL?)
  case checking(PythonEnvironmentCandidate)
  case ready(PythonEnvironmentDetails, workingDirectory: URL)
  case invalid(PythonEnvironmentCandidate, PythonPreflightFailure)
  case needsWorkingDirectory(PythonEnvironmentDetails)
}
