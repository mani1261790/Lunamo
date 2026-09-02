import CryptoKit
import Darwin
import Foundation
import MarimoDomain

public enum DocumentOpenError: Error, Sendable, Equatable {
  case fileTooLarge(Int)
  case invalidUTF8
  case readFailed(String)
}

public struct DocumentSourceSnapshot: Sendable, Equatable {
  public let source: String
  public let identity: FileIdentity
}

public actor DocumentService {
  public static let maximumSourceBytes = 20 * 1024 * 1024

  public init() {}

  public func readSource(at url: URL) throws -> String {
    try readSnapshot(at: url).source
  }

  public func readSnapshot(at url: URL) throws -> DocumentSourceSnapshot {
    do {
      let snapshot: (data: Data, information: stat)
      do {
        snapshot = try readStableFileSnapshot(at: url, maximumBytes: Self.maximumSourceBytes)
      } catch StableFileReadError.fileTooLarge(let size) {
        throw DocumentOpenError.fileTooLarge(size)
      }
      let information = snapshot.information
      guard information.st_mode & S_IFMT == S_IFREG else {
        throw DocumentOpenError.readFailed("Not a regular file: \(url.path)")
      }
      let diskData = snapshot.data
      guard diskData.count <= Self.maximumSourceBytes else {
        throw DocumentOpenError.fileTooLarge(diskData.count)
      }
      var sourceData = diskData
      if sourceData.starts(with: [0xEF, 0xBB, 0xBF]) {
        sourceData.removeFirst(3)
      }
      guard let source = String(data: sourceData, encoding: .utf8) else {
        throw DocumentOpenError.invalidUTF8
      }
      let identity = FileIdentity(
        volumeIdentifier: String(information.st_dev),
        fileIdentifier: String(information.st_ino),
        modificationDate: Date(
          timeIntervalSince1970: Double(information.st_mtimespec.tv_sec)
            + Double(information.st_mtimespec.tv_nsec) / 1_000_000_000
        ),
        size: UInt64(information.st_size),
        contentSHA256: SHA256.hash(data: diskData).map { String(format: "%02x", $0) }.joined()
      )
      return DocumentSourceSnapshot(source: source, identity: identity)
    } catch let error as DocumentOpenError {
      throw error
    } catch {
      throw DocumentOpenError.readFailed(error.localizedDescription)
    }
  }

}
