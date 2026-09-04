import MarimoApplication
import SwiftUI

struct NotebookSidebarView: View {
  @ObservedObject var store: NotebookStore

  var body: some View {
    List {
      if store.notebookDirectoryURL == nil {
        ContentUnavailableView(
          "No Folder", systemImage: "folder",
          description: Text("Open a notebook to browse its folder."))
      } else if store.sidebarFiles.isEmpty {
        ContentUnavailableView(
          "No Supported Files", systemImage: "doc",
          description: Text("This folder has no notebooks, data, or images."))
      } else {
        OutlineGroup(store.sidebarFiles, children: \.children) { file in
          fileRow(file)
        }
      }
    }
    .listStyle(.sidebar)
    .navigationTitle("Files")
    .accessibilityLabel("Files")
    .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 360)
  }

  private func icon(for kind: NotebookSidebarFile.Kind) -> String {
    switch kind {
    case .directory: "folder"
    case .notebook: "doc.text"
    case .data: "tablecells"
    case .image: "photo"
    }
  }

  @ViewBuilder
  private func fileRow(_ file: NotebookSidebarFile) -> some View {
    if file.kind == .notebook {
      Button {
        Task { await store.openSidebarFile(file) }
      } label: {
        Label(file.name, systemImage: icon(for: file.kind)).lineLimit(1)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(localizedUI("Open notebook %@", file.name))
    } else {
      Label(file.name, systemImage: icon(for: file.kind)).lineLimit(1)
        .accessibilityLabel(file.name)
    }
  }
}
