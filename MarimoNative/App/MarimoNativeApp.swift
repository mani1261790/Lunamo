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
    startupURL = CommandLine.arguments.dropFirst().first.map {
      URL(fileURLWithPath: $0).standardizedFileURL
    }
  }

  var body: some Scene {
    WindowGroup {
      NotebookRootView(store: store, startupURL: startupURL)
    }
    .defaultSize(width: 1_200, height: 800)
  }
}
