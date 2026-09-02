import Foundation
import MarimoProcess

private struct PreflightPayload: Decodable {
  let executable: String
  let python: [Int]
  let architecture: String
  let marimoVersion: String
  let marimoFile: String

  enum CodingKeys: String, CodingKey {
    case executable
    case python
    case architecture
    case marimoVersion = "marimo_version"
    case marimoFile = "marimo_file"
  }
}

private struct ProcessCapture: Sendable {
  var stdout = Data()
  var stderr = Data()
  var status: Int32 = -1
}

public actor PythonPreflightService {
  public static let timeout: Duration = .seconds(5)
  public static let outputLimit = 64 * 1024
  public static let requiredMarimoVersion = "0.24.0"
  public static let fixedScript = """
    import json, os, platform, sys
    import marimo
    print(json.dumps({
        "executable": os.path.realpath(sys.executable),
        "python": [sys.version_info.major, sys.version_info.minor, sys.version_info.micro],
        "architecture": platform.machine(),
        "marimo_version": marimo.__version__,
        "marimo_file": os.path.realpath(marimo.__file__),
    }, separators=(",", ":")))
    """

  private let makeTransport: @Sendable () -> any ProcessTransport
  private let timeout: Duration

  public init(
    timeout: Duration = PythonPreflightService.timeout,
    makeTransport: @escaping @Sendable () -> any ProcessTransport = { LSPProcess() }
  ) {
    self.timeout = timeout
    self.makeTransport = makeTransport
  }

  public func inspect(_ candidate: PythonEnvironmentCandidate) async throws
    -> PythonEnvironmentDetails
  {
    let launchURL = normalizedExecutableURL(candidate.executableURL)
    let identity = try executableIdentity(at: launchURL)
    if let expectedIdentity = candidate.expectedIdentity, expectedIdentity != identity {
      throw PythonPreflightFailure.executableChanged(launchURL)
    }
    let request = ProcessLaunchRequest(
      executableURL: launchURL,
      arguments: ["-I", "-c", Self.fixedScript],
      environment: [
        "LANG": "en_US.UTF-8",
        "PATH": "/usr/bin:/bin",
        "PYTHONNOUSERSITE": "1",
        "PYTHONUTF8": "1",
      ]
    )
    let transport = makeTransport()
    let result: ProcessCapture
    do {
      result = try await capture(transport: transport, request: request)
    } catch let failure as PythonPreflightFailure {
      throw failure
    } catch {
      throw PythonPreflightFailure.launchFailed(error.localizedDescription)
    }
    guard result.status == 0 else {
      throw PythonPreflightFailure.nonzeroExit(result.status)
    }
    guard let payload = try? JSONDecoder().decode(PreflightPayload.self, from: result.stdout),
      payload.python.count == 3
    else { throw PythonPreflightFailure.invalidJSON }

    let reportedURL = canonicalURL(URL(fileURLWithPath: payload.executable))
    let expectedRealURL = URL(fileURLWithPath: identity.canonicalPath).standardizedFileURL
    guard reportedURL == expectedRealURL else {
      throw PythonPreflightFailure.executableMismatch(
        expected: expectedRealURL, reported: reportedURL
      )
    }
    let version = PythonVersion(
      major: payload.python[0], minor: payload.python[1], patch: payload.python[2]
    )
    guard version.major == 3, (10...14).contains(version.minor) else {
      throw PythonPreflightFailure.unsupportedPython(version)
    }
    guard payload.architecture == "arm64" else {
      throw PythonPreflightFailure.unsupportedArchitecture(payload.architecture)
    }
    guard payload.marimoVersion == Self.requiredMarimoVersion else {
      throw PythonPreflightFailure.unsupportedMarimo(payload.marimoVersion)
    }
    let finalIdentity = try executableIdentity(at: launchURL)
    guard finalIdentity == identity else {
      throw PythonPreflightFailure.executableChanged(launchURL)
    }
    return PythonEnvironmentDetails(
      executableURL: launchURL,
      realExecutableURL: reportedURL,
      pythonVersion: version,
      architecture: payload.architecture,
      marimoVersion: payload.marimoVersion,
      marimoModuleURL: canonicalURL(URL(fileURLWithPath: payload.marimoFile)),
      kind: candidate.kind,
      identity: identity
    )
  }

  private func capture(
    transport: any ProcessTransport,
    request: ProcessLaunchRequest
  ) async throws -> ProcessCapture {
    let timeout = self.timeout
    let stream: AsyncStream<ProcessEvent>
    do {
      stream = try await transport.start(request)
    } catch {
      throw PythonPreflightFailure.launchFailed(error.localizedDescription)
    }
    do {
      return try await withThrowingTaskGroup(of: ProcessCapture.self) { group in
        group.addTask {
          var capture = ProcessCapture()
          for await event in stream {
            try Task.checkCancellation()
            switch event {
            case .stdout(let data):
              guard capture.stdout.count + data.count <= Self.outputLimit else {
                await transport.forceTerminate()
                throw PythonPreflightFailure.stdoutLimitExceeded
              }
              capture.stdout.append(data)
            case .stderr(let data):
              guard capture.stderr.count + data.count <= Self.outputLimit else {
                await transport.forceTerminate()
                throw PythonPreflightFailure.stderrLimitExceeded
              }
              capture.stderr.append(data)
            case .terminated(let status):
              capture.status = status
              return capture
            }
          }
          throw PythonPreflightFailure.launchFailed("Process ended without a termination status.")
        }
        group.addTask {
          try await Task.sleep(for: timeout)
          throw PythonPreflightFailure.timedOut
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else {
          throw PythonPreflightFailure.launchFailed("Preflight produced no result.")
        }
        return first
      }
    } catch {
      await transport.forceTerminate()
      throw error
    }
  }
}
