import CryptoKit
import Darwin
import Foundation
import MarimoDomain

public enum AtomicWriteExpectation: Sendable, Equatable {
  case unchecked
  case missing
  case matching(FileIdentity)
}

public enum AtomicWriteError: Error, Sendable, Equatable {
  case conflict(URL)
  case invalidTarget(URL)
  case operationFailed(URL, Int32)
}

public actor AtomicFileWriter {
  private let beforeReplace: (@Sendable (URL) throws -> Void)?

  public init() {
    beforeReplace = nil
  }

  init(beforeReplace: @escaping @Sendable (URL) throws -> Void) {
    self.beforeReplace = beforeReplace
  }

  public func identity(at url: URL) throws -> FileIdentity {
    let snapshot = try readStableFileSnapshot(at: url)
    let information = snapshot.information
    guard information.st_mode & S_IFMT == S_IFREG else {
      throw AtomicWriteError.invalidTarget(url)
    }
    return FileIdentity(
      volumeIdentifier: String(information.st_dev),
      fileIdentifier: String(information.st_ino),
      modificationDate: Date(
        timeIntervalSince1970: Double(information.st_mtimespec.tv_sec)
          + Double(information.st_mtimespec.tv_nsec) / 1_000_000_000
      ),
      size: UInt64(information.st_size),
      contentSHA256: Self.sha256(snapshot.data)
    )
  }

  @discardableResult
  public func write(
    source: String,
    to target: URL,
    expecting expectation: AtomicWriteExpectation
  ) throws -> FileIdentity {
    let target = target.standardizedFileURL
    let directory = target.deletingLastPathComponent()
    let temporary = directory.appending(
      path: ".\(target.lastPathComponent).marimonative-\(UUID().uuidString).tmp"
    )
    let manager = FileManager.default
    guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
      throw AtomicWriteError.invalidTarget(target)
    }
    try verify(expectation, for: target)

    do {
      try Data(source.utf8).write(to: temporary, options: [.withoutOverwriting])
      defer { try? manager.removeItem(at: temporary) }

      if manager.fileExists(atPath: target.path),
        let permissions = try manager.attributesOfItem(atPath: target.path)[.posixPermissions]
          as? NSNumber
      {
        try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporary.path)
      }
      let handle = try FileHandle(forWritingTo: temporary)
      try handle.synchronize()
      try handle.close()

      try beforeReplace?(target)
      try verify(expectation, for: target)
      if manager.fileExists(atPath: target.path) {
        _ = try manager.replaceItemAt(
          target,
          withItemAt: temporary,
          backupItemName: nil,
          options: [.usingNewMetadataOnly]
        )
      } else {
        try manager.moveItem(at: temporary, to: target)
      }
      try synchronizeDirectory(directory)
      return try identity(at: target)
    } catch let error as AtomicWriteError {
      throw error
    } catch let error as CocoaError {
      throw AtomicWriteError.operationFailed(target, Int32(error.errorCode))
    } catch let error as POSIXError {
      throw AtomicWriteError.operationFailed(target, error.code.rawValue)
    } catch {
      throw AtomicWriteError.operationFailed(target, EIO)
    }
  }

  private func verify(_ expectation: AtomicWriteExpectation, for target: URL) throws {
    switch expectation {
    case .unchecked:
      return
    case .missing:
      guard !FileManager.default.fileExists(atPath: target.path) else {
        throw AtomicWriteError.conflict(target)
      }
    case .matching(let expected):
      guard FileManager.default.fileExists(atPath: target.path),
        try identity(at: target) == expected
      else { throw AtomicWriteError.conflict(target) }
    }
  }

  private func synchronizeDirectory(_ directory: URL) throws {
    let descriptor = directory.withUnsafeFileSystemRepresentation { path in
      path.map { Darwin.open($0, O_RDONLY) } ?? -1
    }
    guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    defer { Darwin.close(descriptor) }
    guard Darwin.fsync(descriptor) == 0 else {
      throw POSIXError(.init(rawValue: errno) ?? .EIO)
    }
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

enum StableFileReadError: Error {
  case fileTooLarge(Int)
}

func readStableFileSnapshot(
  at url: URL,
  maximumBytes: Int? = nil
) throws -> (data: Data, information: stat) {
  let descriptor = url.withUnsafeFileSystemRepresentation { path in
    path.map { Darwin.open($0, O_RDONLY) } ?? -1
  }
  guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
  let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)

  var before = stat()
  guard Darwin.fstat(descriptor, &before) == 0 else {
    try? handle.close()
    throw POSIXError(.init(rawValue: errno) ?? .EIO)
  }
  if let maximumBytes, before.st_size > maximumBytes {
    try? handle.close()
    throw StableFileReadError.fileTooLarge(Int(before.st_size))
  }
  let data = try handle.readToEnd() ?? Data()
  var after = stat()
  guard Darwin.fstat(descriptor, &after) == 0 else {
    try? handle.close()
    throw POSIXError(.init(rawValue: errno) ?? .EIO)
  }
  try handle.close()
  guard
    before.st_dev == after.st_dev,
    before.st_ino == after.st_ino,
    before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
    before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
    before.st_size == after.st_size,
    data.count == after.st_size
  else { throw AtomicWriteError.conflict(url) }
  return (data, after)
}
