import Foundation
import MarimoApplication
import MarimoBackend
import MarimoUI
import SwiftUI

@main
struct MarimoNativeApp: App {
  @StateObject private var store: NotebookStore
  private let startupURL: URL?

  init() {
    let sidecar = Bundle.main.resourceURL?.appending(path: "Sidecar")
    let backend: any MarimoBackend
    if let sidecar, let adapter = try? MarimoLSPAdapter(sidecarDirectory: sidecar) {
      backend = adapter
    } else {
      backend = PlaceholderMarimoBackend()
    }
    _store = StateObject(wrappedValue: NotebookStore(backend: backend))
    startupURL = CommandLine.arguments.dropFirst().first(where: {
      URL(fileURLWithPath: $0).pathExtension.lowercased() == "py"
    }).map {
      URL(fileURLWithPath: $0).standardizedFileURL
    }
  }

  var body: some Scene {
    Window("MarimoNative", id: "notebook") {
      NotebookRootView(store: store, startupURL: startupURL)
    }
    .defaultSize(width: 1_320, height: 800)
    .windowResizability(.contentSize)
    .commands {
      CommandGroup(replacing: .newItem) {}
      NotebookMenuCommands(store: store)
    }
  }
}
