import Foundation

public struct ProcessLaunchRequest: Sendable, Equatable {
  public let executableURL: URL
  public let arguments: [String]
  public let environment: [String: String]

  public init(
    executableURL: URL,
    arguments: [String],
    environment: [String: String] = [:]
  ) {
    self.executableURL = executableURL
    self.arguments = arguments
    self.environment = environment
  }
}
