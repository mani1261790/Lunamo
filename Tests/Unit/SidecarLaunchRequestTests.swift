import Foundation
import MarimoProcess
import Testing

@Suite("Sidecar launch request")
struct SidecarLaunchRequestTests {
  @Test("Bundled Python is launched directly with an isolated environment")
  func directLaunch() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let sidecar = root.appending(path: ".build/Sidecar")
    guard FileManager.default.fileExists(atPath: sidecar.path) else {
      Issue.record("Build .build/Sidecar before running sidecar tests")
      return
    }
    let request = try SidecarLaunchRequest.make(sidecarDirectory: sidecar)
    #expect(request.executableURL == sidecar.appending(path: "bin/python3"))
    #expect(request.arguments == [sidecar.appending(path: "launch_marimo_lsp.py").path])
    #expect(request.environment["PYTHONNOUSERSITE"] == "1")
    #expect(request.environment["PYTHONUTF8"] == "1")
    #expect(!request.arguments.contains("-c"))
    #expect(!request.executableURL.path.contains("/bin/sh"))
    #expect(!request.executableURL.path.contains("/zsh"))
  }
}
