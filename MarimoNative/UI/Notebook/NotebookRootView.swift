import Foundation
import MarimoApplication
import SwiftUI

public struct NotebookRootView: View {
  @ObservedObject private var store: NotebookStore
  private let startupURL: URL?

  public init(store: NotebookStore, startupURL: URL? = nil) {
    self.store = store
    self.startupURL = startupURL
  }

  public var body: some View {
    NavigationSplitView {
      List {
        Label("Files", systemImage: "folder")
        Label("Cells", systemImage: "list.number")
      }
      .navigationTitle("MarimoNative")
    } detail: {
      ScrollView {
        LazyVStack(spacing: 16) {
          openStateBanner
          ForEach(store.document.cells) { cell in
            CellView(
              cell: cell,
              selected: store.document.selectedCellID == cell.runtimeID,
              send: store.send
            )
          }
        }
        .frame(maxWidth: 1_100)
        .padding()
        .frame(maxWidth: .infinity)
      }
      .navigationTitle(store.document.sourceURL?.lastPathComponent ?? "Untitled")
      .toolbar {
        ToolbarItemGroup {
          Button("Add Cell", systemImage: "plus") {
            store.send(.addCell)
          }
          Text(store.backendStatus == .ready ? "Backend Ready" : "Backend Offline")
            .foregroundStyle(.secondary)
        }
      }
    }
    .frame(minWidth: 960, minHeight: 640)
    .task {
      await store.startBackend()
      if let startupURL {
        await store.open(startupURL)
      }
    }
    .onOpenURL { url in
      Task { await store.open(url) }
    }
  }

  @ViewBuilder
  private var openStateBanner: some View {
    switch store.openState {
    case .idle, .loaded:
      EmptyView()
    case .loading(let url):
      ProgressView("Opening \(url.lastPathComponent)…")
        .frame(maxWidth: .infinity, alignment: .leading)
    case .invalidSyntax(let url, let line, let column):
      ContentUnavailableView(
        "Python syntax error",
        systemImage: "exclamationmark.triangle",
        description: Text(
          "\(url.lastPathComponent), line \(line.map(String.init) ?? "unknown"), column \(column.map(String.init) ?? "unknown")"
        )
      )
    case .convertible(let url):
      ContentUnavailableView(
        "Regular Python file",
        systemImage: "doc.badge.ellipsis",
        description: Text("\(url.lastPathComponent) was not overwritten or executed.")
      )
    case .failed(let url, let message):
      ContentUnavailableView(
        "Could not open \(url.lastPathComponent)",
        systemImage: "xmark.octagon",
        description: Text(message)
      )
    }
  }
}
