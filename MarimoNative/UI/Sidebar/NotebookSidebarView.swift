import MarimoApplication
import MarimoDomain
import SwiftUI

struct NotebookSidebarView: View {
  @ObservedObject var store: NotebookStore

  var body: some View {
    List(selection: selectedCellBinding) {
      Section("Files") {
        if store.notebookDirectoryURL == nil {
          ContentUnavailableView(
            "No Folder", systemImage: "folder",
            description: Text("Open a notebook to browse its folder."))
        } else if store.sidebarFiles.isEmpty {
          Text("No Supported Files").foregroundStyle(.secondary)
        } else {
          OutlineGroup(store.sidebarFiles, children: \.children) { file in
            fileRow(file)
          }
        }
      }

      Section("Cells") {
        ForEach(Array(store.document.cells.enumerated()), id: \.element.runtimeID) { index, cell in
          Button {
            Task { await store.send(.selectCell(cell.runtimeID)) }
          } label: {
            VStack(alignment: .leading, spacing: 3) {
              HStack {
                Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary)
                Text(cell.name).font(.caption.monospaced()).lineLimit(1)
                Spacer()
                Image(systemName: statusIcon(cell.runtime.status))
                  .foregroundStyle(statusColor(cell.runtime.status))
              }
              Text(localizedSummary(cell)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
          }
          .buttonStyle(.plain)
          .tag(cell.runtimeID)
          .accessibilityLabel(localizedUI("Cell %ld, %@", index + 1, cell.name))
          .accessibilityValue("\(statusLabel(cell.runtime.status)), \(localizedSummary(cell))")
        }
      }
    }
    .navigationTitle("MarimoNative")
    .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 360)
  }

  private var selectedCellBinding: Binding<UUID?> {
    Binding(
      get: { store.document.selectedCellID },
      set: { value in
        guard let value else { return }
        Task { await store.send(.selectCell(value)) }
      }
    )
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

  private func localizedSummary(_ cell: NotebookCellState) -> String {
    cell.sidebarSummary == "Empty cell" ? localizedUI("Empty cell") : cell.sidebarSummary
  }
}

func statusLabel(_ status: ExecutionStatus) -> String {
  switch status {
  case .idle: localizedUI("Idle")
  case .queued: localizedUI("Queued")
  case .running: localizedUI("Running")
  case .error: localizedUI("Error")
  case .disabledTransitively: localizedUI("Disabled")
  }
}

private func statusIcon(_ status: ExecutionStatus) -> String {
  switch status {
  case .idle: "circle"
  case .queued: "clock"
  case .running: "progress.indicator"
  case .error: "exclamationmark.circle.fill"
  case .disabledTransitively: "slash.circle"
  }
}

private func statusColor(_ status: ExecutionStatus) -> Color {
  switch status {
  case .running: .accentColor
  case .error: .red
  default: .secondary
  }
}
