import Foundation
import OSLog

public enum MarimoLog {
  private static let subsystem = "dev.marimonative.app"

  public static let app = Logger(subsystem: subsystem, category: "app")
  public static let document = Logger(subsystem: subsystem, category: "document")
  public static let lsp = Logger(subsystem: subsystem, category: "lsp")
  public static let kernel = Logger(subsystem: subsystem, category: "kernel")
  public static let output = Logger(subsystem: subsystem, category: "output")
  public static let widget = Logger(subsystem: subsystem, category: "widget")
  public static let web = Logger(subsystem: subsystem, category: "web")
}

public enum MarimoLogPrivacy {
  public static func redactHomePrefix(
    in value: String,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> String {
    let home = homeDirectory.standardizedFileURL.path
    guard !home.isEmpty, home != "/" else { return value }
    if value == home { return "~" }
    return value.replacingOccurrences(of: home + "/", with: "~/")
  }
}
