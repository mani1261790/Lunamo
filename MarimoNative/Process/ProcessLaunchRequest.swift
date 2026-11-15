import Foundation

public struct ProcessLaunchRequest: Sendable, Equatable {
  public let executableURL: URL
  public let arguments: [String]
  public let environment: [String: String]
  public let currentDirectoryURL: URL?

  public init(
    executableURL: URL,
    arguments: [String],
    environment: [String: String] = [:],
    currentDirectoryURL: URL? = nil
  ) {
    self.executableURL = executableURL
    self.arguments = arguments
    self.environment = environment
    self.currentDirectoryURL = currentDirectoryURL
  }
}
