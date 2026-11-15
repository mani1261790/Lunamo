import Foundation
import MarimoApplication
import MarimoBackend
import MarimoDomain
import MarimoEnvironment
import MarimoUI
import SwiftUI

@main
struct LunamoApp: App {
  @NSApplicationDelegateAdaptor(MarimoAppDelegate.self) private var appDelegate
  @StateObject private var updater = LunamoUpdater()
  @StateObject private var store: NotebookStore
  private let startupURL: URL?

  init() {
    try? TemporaryOutputStore.shared.cleanupExpired()
    MarimoLog.app.info("Application started")
    let sidecar = Bundle.main.resourceURL?.appending(path: "Sidecar")
    let backend: any MarimoBackend
    if let sidecar, let adapter = try? MarimoLSPAdapter(sidecarDirectory: sidecar) {
      backend = adapter
    } else {
      backend = PlaceholderMarimoBackend()
    }
    if let document = ReleasePerformanceProbe.fixtureDocument {
      _store = StateObject(
        wrappedValue: NotebookStore(
          backend: backend,
          document: document,
          environmentDiscovery: PythonEnvironmentDiscovery(
            bundledPythonURL: sidecar?.appending(path: "bin/python3")
          ),
          packageManager: sidecar.map {
            UVNotebookPackageManager(uvURL: $0.appending(path: "bin/uv"))
          }
        )
      )
    } else {
      _store = StateObject(
        wrappedValue: NotebookStore(
          backend: backend,
          environmentDiscovery: PythonEnvironmentDiscovery(
            bundledPythonURL: sidecar?.appending(path: "bin/python3")
          ),
          packageManager: sidecar.map {
            UVNotebookPackageManager(uvURL: $0.appending(path: "bin/uv"))
          }
        )
      )
    }
    if CommandLine.arguments.contains("--performance-window-marker"),
      let performanceNotebook = ProcessInfo.processInfo.environment[
        "MARIMONATIVE_PERFORMANCE_NOTEBOOK"]
    {
      startupURL = URL(fileURLWithPath: performanceNotebook).standardizedFileURL
    } else {
      startupURL = CommandLine.arguments.dropFirst().first(where: {
        ["py", "ipynb"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased())
      }).map {
        URL(fileURLWithPath: $0).standardizedFileURL
      }
    }
  }

  var body: some Scene {
    Window("Lunamo", id: "notebook") {
      NotebookRootView(store: store, startupURL: startupURL)
        .onAppear {
          appDelegate.store = store
          ReleasePerformanceProbe.recordWindowPresented()
          ReleasePerformanceProbe.recordLoadedCellCount(store.document.cells.count)
          ReleasePerformanceProbe.recordBackendStatus(store.backendStatus)
          Task { await ReleasePerformanceProbe.runScrollProbe() }
          Task { await ReleaseAcceptanceProbe.run(store: store) }
        }
        .onChange(of: store.document.cells.count) { _, count in
          ReleasePerformanceProbe.recordLoadedCellCount(count)
        }
        .onChange(of: store.backendStatus) { _, status in
          ReleasePerformanceProbe.recordBackendStatus(status)
        }
    }
    .defaultSize(width: 1_320, height: 800)
    .windowResizability(.contentMinSize)
    .windowStyle(.hiddenTitleBar)
    .commands {
      NotebookMenuCommands(store: store)
      LunamoUpdateCommands(updater: updater)
    }

    Settings {
      NotebookSettingsView(store: store)
    }
  }
}
