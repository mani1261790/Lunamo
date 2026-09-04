import Foundation

public enum SidecarLaunchError: Error, Sendable, Equatable {
  case missingExecutable(URL)
  case missingLauncher(URL)
}

public enum SidecarLaunchRequest {
  public static func make(sidecarDirectory: URL) throws -> ProcessLaunchRequest {
    let executable = sidecarDirectory.appending(path: "bin/python3")
    let launcher = sidecarDirectory.appending(path: "launch_marimo_lsp.py")
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
      throw SidecarLaunchError.missingExecutable(executable)
    }
    guard FileManager.default.fileExists(atPath: launcher.path) else {
      throw SidecarLaunchError.missingLauncher(launcher)
    }
    return ProcessLaunchRequest(
      executableURL: executable,
      arguments: [launcher.path],
      environment: [
        "LANG": "en_US.UTF-8",
        "PATH": "\(sidecarDirectory.appending(path: "bin").path):/usr/bin:/bin",
        "PYTHONNOUSERSITE": "1",
        "PYTHONUTF8": "1",
      ]
    )
  }
}
