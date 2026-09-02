import Foundation
import MarimoDomain
import MarimoProcess
import Testing

@Suite("Privacy logging and temporary output")
struct PrivacyAndTemporaryOutputTests {
  @Test("Home paths are redacted from release-visible diagnostic text")
  func homePathRedaction() async {
    let home = URL(fileURLWithPath: "/Users/example")
    #expect(
      MarimoLogPrivacy.redactHomePrefix(
        in: "failure at /Users/example/project/notebook.py", homeDirectory: home)
        == "failure at ~/project/notebook.py"
    )
    let buffer = BoundedStderrBuffer()
    await buffer.append(
      "failure at \(FileManager.default.homeDirectoryForCurrentUser.path)/private.py\n")
    #expect(await buffer.snapshot() == ["failure at ~/private.py"])
  }

  @Test("Session output is removed and directories older than 24 hours are cleaned")
  func temporaryOutputLifecycle() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let now = Date()
    let stale = root.appending(path: "stale", directoryHint: .isDirectory)
    let recent = root.appending(path: "recent", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: false)
    try FileManager.default.createDirectory(at: recent, withIntermediateDirectories: false)
    try FileManager.default.setAttributes(
      [.modificationDate: now.addingTimeInterval(-TemporaryOutputStore.maximumAge - 1)],
      ofItemAtPath: stale.path
    )

    let store = TemporaryOutputStore(rootURL: root, now: now)
    #expect(!FileManager.default.fileExists(atPath: stale.path))
    #expect(FileManager.default.fileExists(atPath: recent.path))
    let document = try store.makeDocumentDirectory()
    try Data("private output".utf8).write(to: document.appending(path: "index.html"))
    #expect(FileManager.default.fileExists(atPath: document.path))
    store.endSession()
    #expect(!FileManager.default.fileExists(atPath: store.sessionURL.path))
  }

  @Test("Logging declares all categories without telemetry or crash attachments")
  func loggingArchitecture() throws {
    let root = repositoryRoot()
    let logging = try String(
      contentsOf: root.appending(path: "MarimoNative/Domain/MarimoLogging.swift"),
      encoding: .utf8
    )
    for category in ["app", "document", "lsp", "kernel", "output", "widget", "web"] {
      #expect(logging.contains("category: \"\(category)\""))
    }
    let sources = try FileManager.default.subpathsOfDirectory(
      atPath: root.appending(path: "MarimoNative").path
    ).filter { $0.hasSuffix(".swift") }.map {
      try String(contentsOf: root.appending(path: "MarimoNative/\($0)"), encoding: .utf8)
    }.joined(separator: "\n")
    for forbidden in [
      "Crashlytics", "SentrySDK", "TelemetryClient", "sourceAttachment", "outputAttachment",
    ] {
      #expect(!sources.contains(forbidden))
    }
    let connection = try String(
      contentsOf: root.appending(path: "MarimoNative/Backend/JSONRPCConnection.swift"),
      encoding: .utf8
    )
    for metadata in ["method=", "id=", "op=", "bytes=", "duration="] {
      #expect(connection.contains(metadata))
    }
    #expect(!connection.contains("logger.debug(\"params"))
    #expect(!connection.contains("logger.info(\"params"))

    let appDelegate = try String(
      contentsOf: root.appending(path: "MarimoNative/App/MarimoAppDelegate.swift"),
      encoding: .utf8
    )
    let session = try String(
      contentsOf: root.appending(path: "MarimoNative/Application/NotebookSession.swift"),
      encoding: .utf8
    )
    #expect(appDelegate.contains("TemporaryOutputStore.shared.endSession()"))
    #expect(!session.contains("TemporaryOutputStore.shared.endSession()"))
  }

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  }
}
