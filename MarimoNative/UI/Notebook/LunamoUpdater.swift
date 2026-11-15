import Combine
import Sparkle
import SwiftUI

/// One updater per application. Automated acceptance must remain network-independent.
@MainActor
public final class LunamoUpdater: ObservableObject {
  @Published public private(set) var canCheckForUpdates = false
  private let controller: SPUStandardUpdaterController

  public init() {
    let isProbe = CommandLine.arguments.contains {
      $0.hasPrefix("--release-acceptance-") || $0.hasPrefix("--performance-")
    }
    controller = SPUStandardUpdaterController(
      startingUpdater: !isProbe, updaterDelegate: nil, userDriverDelegate: nil
    )
    if !isProbe {
      controller.updater.publisher(for: \.canCheckForUpdates)
        .assign(to: &$canCheckForUpdates)
    }
  }

  public func checkForUpdates() {
    controller.updater.checkForUpdates()
  }
}

public struct LunamoUpdateCommands: Commands {
  @ObservedObject private var updater: LunamoUpdater

  public init(updater: LunamoUpdater) {
    self.updater = updater
  }

  public var body: some Commands {
    CommandGroup(after: .appInfo) {
      Button(String(localized: "Check for Updates…")) {
        updater.checkForUpdates()
      }
      .disabled(!updater.canCheckForUpdates)
    }
  }
}
