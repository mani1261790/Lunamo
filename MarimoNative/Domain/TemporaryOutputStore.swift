import Foundation

public final class TemporaryOutputStore: @unchecked Sendable {
  public static let maximumAge: TimeInterval = 24 * 60 * 60
  public static let shared = TemporaryOutputStore()

  public let rootURL: URL
  public let sessionURL: URL

  private let manager: FileManager
  private let lock = NSLock()

  public init(
    rootURL: URL = FileManager.default.temporaryDirectory.appending(
      path: "MarimoNative-TemporaryOutputs", directoryHint: .isDirectory),
    manager: FileManager = .default,
    now: Date = Date()
  ) {
    self.rootURL = rootURL.standardizedFileURL
    sessionURL = self.rootURL.appending(
      path: UUID().uuidString, directoryHint: .isDirectory)
    self.manager = manager
    try? cleanupExpired(now: now)
  }

  public func makeDocumentDirectory() throws -> URL {
    try lock.withLock {
      try manager.createDirectory(at: sessionURL, withIntermediateDirectories: true)
      let directory = sessionURL.appending(
        path: UUID().uuidString, directoryHint: .isDirectory)
      try manager.createDirectory(at: directory, withIntermediateDirectories: false)
      return directory
    }
  }

  public func removeDocumentDirectory(_ directory: URL) {
    lock.withLock {
      guard directory.standardizedFileURL.deletingLastPathComponent() == sessionURL else { return }
      try? manager.removeItem(at: directory)
    }
  }

  public func endSession() {
    lock.withLock { try? manager.removeItem(at: sessionURL) }
  }

  public func cleanupExpired(now: Date = Date()) throws {
    try lock.withLock {
      guard manager.fileExists(atPath: rootURL.path) else { return }
      let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
      for directory in try manager.contentsOfDirectory(
        at: rootURL,
        includingPropertiesForKeys: Array(keys),
        options: [.skipsHiddenFiles]
      ) {
        let values = try directory.resourceValues(forKeys: keys)
        guard values.isDirectory == true, let modified = values.contentModificationDate,
          now.timeIntervalSince(modified) >= Self.maximumAge
        else { continue }
        try manager.removeItem(at: directory)
      }
    }
  }
}
