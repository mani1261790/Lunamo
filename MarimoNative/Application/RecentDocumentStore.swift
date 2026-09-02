import Foundation

public actor RecentDocumentStore {
  public static let maximumCount = 12
  public static let defaultFileURL: URL = {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
      0]
    return support.appending(path: "MarimoNative/recent-documents.json")
  }()

  private let fileURL: URL

  public init(fileURL: URL = RecentDocumentStore.defaultFileURL) {
    self.fileURL = fileURL.standardizedFileURL
  }

  public func load() -> [URL] {
    guard let data = try? Data(contentsOf: fileURL),
      let paths = try? JSONDecoder().decode([String].self, from: data)
    else { return [] }
    return paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
      .filter { FileManager.default.fileExists(atPath: $0.path) }
  }

  public func record(_ url: URL) throws -> [URL] {
    let canonical = url.standardizedFileURL
    var urls = load().filter { $0 != canonical }
    urls.insert(canonical, at: 0)
    urls = Array(urls.prefix(Self.maximumCount))
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(urls.map(\.path))
    try data.write(to: fileURL, options: [.atomic])
    return urls
  }

  public func remove(_ url: URL) throws -> [URL] {
    let canonical = url.standardizedFileURL
    let urls = load().filter { $0 != canonical }
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(urls.map(\.path))
    try data.write(to: fileURL, options: [.atomic])
    return urls
  }
}
