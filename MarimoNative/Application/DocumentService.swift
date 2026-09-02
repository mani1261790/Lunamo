import Foundation

public enum DocumentOpenError: Error, Sendable, Equatable {
  case fileTooLarge(Int)
  case invalidUTF8
  case readFailed(String)
}

public actor DocumentService {
  public static let maximumSourceBytes = 20 * 1024 * 1024

  public init() {}

  public func readSource(at url: URL) throws -> String {
    do {
      let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
      guard values.isRegularFile == true else {
        throw DocumentOpenError.readFailed("Not a regular file: \(url.path)")
      }
      if let size = values.fileSize, size > Self.maximumSourceBytes {
        throw DocumentOpenError.fileTooLarge(size)
      }
      var data = try Data(contentsOf: url, options: [.mappedIfSafe])
      guard data.count <= Self.maximumSourceBytes else {
        throw DocumentOpenError.fileTooLarge(data.count)
      }
      if data.starts(with: [0xEF, 0xBB, 0xBF]) {
        data.removeFirst(3)
      }
      guard let source = String(data: data, encoding: .utf8) else {
        throw DocumentOpenError.invalidUTF8
      }
      return source
    } catch let error as DocumentOpenError {
      throw error
    } catch {
      throw DocumentOpenError.readFailed(error.localizedDescription)
    }
  }
}
