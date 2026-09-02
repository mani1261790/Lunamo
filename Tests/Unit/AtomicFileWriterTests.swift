import Foundation
import Testing

@testable import MarimoApplication

@Suite("Atomic notebook writer", .serialized)
struct AtomicFileWriterTests {
  @Test("Atomic replacement preserves exact bytes and POSIX permissions")
  func successfulReplacement() async throws {
    try await withTemporaryDirectory { directory in
      let target = directory.appending(path: "notebook.py")
      try Data("original\n".utf8).write(to: target)
      try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: 0o640)],
        ofItemAtPath: target.path
      )
      let writer = AtomicFileWriter()
      let expected = try await writer.identity(at: target)
      let source = "line = 'unchanged'\r\n  # trailing spaces  "

      let saved = try await writer.write(
        source: source,
        to: target,
        expecting: .matching(expected)
      )

      #expect(try String(contentsOf: target, encoding: .utf8) == source)
      let reread = try await writer.identity(at: target)
      #expect(saved.volumeIdentifier == reread.volumeIdentifier)
      #expect(saved.fileIdentifier == reread.fileIdentifier)
      #expect(saved.modificationDate == reread.modificationDate)
      #expect(saved.size == reread.size)
      #expect(saved.contentSHA256 == reread.contentSHA256)
      let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
      #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o640)
      #expect(try temporaryFiles(in: directory).isEmpty)
    }
  }

  @Test("A disk conflict leaves the external file untouched")
  func diskConflict() async throws {
    try await withTemporaryDirectory { directory in
      let target = directory.appending(path: "notebook.py")
      try Data("original\n".utf8).write(to: target)
      let writer = AtomicFileWriter()
      let expected = try await writer.identity(at: target)
      try Data("external edit\n".utf8).write(to: target)

      await #expect(throws: AtomicWriteError.conflict(target)) {
        try await writer.write(source: "local edit\n", to: target, expecting: .matching(expected))
      }
      #expect(try String(contentsOf: target, encoding: .utf8) == "external edit\n")
      #expect(try temporaryFiles(in: directory).isEmpty)
    }
  }

  @Test("A permission failure leaves no temporary file")
  func permissionFailureCleanup() async throws {
    try await withTemporaryDirectory { directory in
      let locked = directory.appending(path: "locked", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
      try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: 0o500)],
        ofItemAtPath: locked.path
      )
      defer {
        try? FileManager.default.setAttributes(
          [.posixPermissions: NSNumber(value: 0o700)],
          ofItemAtPath: locked.path
        )
      }
      let target = locked.appending(path: "notebook.py")

      await #expect(throws: AtomicWriteError.self) {
        try await AtomicFileWriter().write(
          source: "value = 1\n",
          to: target,
          expecting: .missing
        )
      }
      #expect(try temporaryFiles(in: locked).isEmpty)
    }
  }

  @Test("A conflict after temporary write removes the temporary file")
  func lateConflictCleansTemporaryFile() async throws {
    try await withTemporaryDirectory { directory in
      let target = directory.appending(path: "notebook.py")
      try Data("original\n".utf8).write(to: target)
      let expected = try await AtomicFileWriter().identity(at: target)
      let writer = AtomicFileWriter { target in
        try Data("external during save\n".utf8).write(to: target)
      }

      await #expect(throws: AtomicWriteError.conflict(target)) {
        try await writer.write(source: "local edit\n", to: target, expecting: .matching(expected))
      }
      #expect(try String(contentsOf: target, encoding: .utf8) == "external during save\n")
      #expect(try temporaryFiles(in: directory).isEmpty)
    }
  }

  private func withTemporaryDirectory(
    _ operation: (URL) async throws -> Void
  ) async throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "marimonative-atomic-writer-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await operation(directory)
  }

  private func temporaryFiles(in directory: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.contains(".marimonative-") }
  }
}
