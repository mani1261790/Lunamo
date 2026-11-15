import Foundation

public enum ApplicationWorkspaceDirectory {
  public static func resolve(fileManager: FileManager = .default) -> URL {
    let applicationSupport =
      fileManager.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first
      ?? fileManager.homeDirectoryForCurrentUser.appending(
        path: "Library/Application Support", directoryHint: .isDirectory)
    let directory =
      applicationSupport
      .appending(path: "MarimoNative", directoryHint: .isDirectory)
      .appending(path: "Notebooks", directoryHint: .isDirectory)
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.standardizedFileURL
  }
}
