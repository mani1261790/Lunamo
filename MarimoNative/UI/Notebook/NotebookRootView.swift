import AppKit
import Foundation
import MarimoApplication
import MarimoDomain
import MarimoEditor
import SwiftUI

public struct NotebookRootView: View {
  @ObservedObject private var store: NotebookStore
  private let startupURL: URL?
  @State private var columnVisibility: NavigationSplitViewVisibility = .all

  public init(store: NotebookStore, startupURL: URL? = nil) {
    self.store = store
    self.startupURL = startupURL
  }

  public var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      List {
        Section("Notebook") {
          Label("Files", systemImage: "folder")
          Label("Cells", systemImage: "list.number")
        }
      }
      .navigationTitle("MarimoNative")
      .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 360)
    } detail: {
      notebookCanvas
        .navigationTitle(documentTitle)
        .toolbar { notebookToolbar }
    }
    .inspector(isPresented: $store.inspectorPresented) {
      inspector
        .inspectorColumnWidth(min: 260, ideal: 300, max: 440)
    }
    .frame(minWidth: 960, idealWidth: 1_320, minHeight: 640, idealHeight: 800)
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

  private var notebookCanvas: some View {
    ScrollView {
      LazyVStack(spacing: 16) {
        openStateBanner
        ForEach(store.document.cells) { cell in
          CellView(
            cell: cell,
            selected: store.document.selectedCellID == cell.runtimeID,
            focused: store.focusedCellID == cell.runtimeID,
            canRun: canRun,
            send: { intent in
              Task { await store.send(intent) }
            },
            focusEditor: {
              store.focusEditor(cell.runtimeID)
            },
            command: { command in
              handle(command, cellID: cell.runtimeID)
            }
          )
        }
      }
      .frame(maxWidth: 1_100)
      .padding()
      .frame(maxWidth: .infinity)
    }
    .background(Color(nsColor: .textBackgroundColor))
    .accessibilityLabel("Notebook canvas")
  }

  @ToolbarContentBuilder
  private var notebookToolbar: some ToolbarContent {
    ToolbarItem(placement: .navigation) {
      Button("Toggle Sidebar", systemImage: "sidebar.left") {
        toggleSidebar()
      }
      .help("Toggle Sidebar (⌃⌘S)")
    }
    ToolbarItem {
      Text(documentTitle)
        .lineLimit(1)
        .accessibilityLabel("Document title: \(documentTitle)")
    }
    ToolbarItem {
      Menu("No Python Environment", systemImage: "chevron.left.forwardslash.chevron.right") {
        Text("Environment selection is configured in Gate C")
      }
      .help("Python Environment")
    }
    ToolbarItem {
      Label(backendLabel, systemImage: backendIcon)
        .foregroundStyle(.secondary)
        .accessibilityValue(backendLabel)
    }
    ToolbarItemGroup {
      Button("Run All", systemImage: "play.fill") {}
        .disabled(!canRun)
        .help("Run All (⇧⌘↩)")
      if store.backendStatus == .ready {
        Button("Interrupt", systemImage: "stop.fill") {}
          .disabled(true)
          .help("Interrupt (⌘.)")
      } else {
        Button("Restart Backend", systemImage: "arrow.clockwise") {
          Task { await store.startBackend() }
        }
      }
      Button("Toggle Inspector", systemImage: "sidebar.right") {
        store.inspectorPresented.toggle()
      }
      .help("Toggle Inspector (⌥⌘I)")
    }
  }

  private var inspector: some View {
    Form {
      Section("Session") {
        LabeledContent("Backend", value: backendLabel)
        LabeledContent("Kernel", value: "Not Started")
        LabeledContent("Environment", value: "Not Configured")
      }
      Section("Variables") {
        ContentUnavailableView(
          "No Variables",
          systemImage: "list.bullet.rectangle",
          description: Text("Run a cell to inspect variables.")
        )
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Inspector")
  }

  private var documentTitle: String {
    store.document.sourceURL?.lastPathComponent ?? "Untitled"
  }

  private var canRun: Bool {
    false
  }

  private var backendLabel: String {
    store.backendStatus == .ready ? "Backend Ready" : "Backend Offline"
  }

  private var backendIcon: String {
    store.backendStatus == .ready ? "checkmark.circle" : "exclamationmark.circle"
  }

  private func toggleSidebar() {
    NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
  }

  private func handle(_ command: CodeEditorCommand, cellID: UUID) {
    switch command {
    case .leaveEditor:
      store.leaveEditor()
    case .moveUp:
      move(cellID, offset: -1)
    case .moveDown:
      move(cellID, offset: 1)
    case .deleteCell:
      guard store.focusedCellID == nil else { return }
      Task { await store.send(.deleteCell(cellID)) }
    case .runAndAdvance, .runAndStay, .runAndInsert, .runAll, .interrupt:
      guard canRun else { return }
    }
  }

  private func move(_ cellID: UUID, offset: Int) {
    guard let index = store.document.cells.firstIndex(where: { $0.runtimeID == cellID }) else {
      return
    }
    Task { await store.send(.moveCell(cellID, to: index + offset)) }
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
