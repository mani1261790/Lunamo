import AppKit
import Foundation
import MarimoApplication
import MarimoDomain
import MarimoEditor
import MarimoEnvironment
import SwiftUI

public struct NotebookRootView: View {
  @ObservedObject private var store: NotebookStore
  private let startupURL: URL?
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorScheme) private var colorScheme

  public init(store: NotebookStore, startupURL: URL? = nil) {
    self.store = store
    self.startupURL = startupURL
  }

  public var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      NotebookSidebarView(store: store)
    } detail: {
      notebookCanvas
        .navigationTitle(documentTitle)
        .toolbar { notebookToolbar }
    }
    .inspector(isPresented: $store.inspectorPresented) {
      NotebookInspectorView(store: store)
        .inspectorColumnWidth(min: 260, ideal: 300, max: 440)
    }
    .frame(minWidth: 960, idealWidth: 1_320, minHeight: 640, idealHeight: 800)
    .transaction { transaction in
      if reduceMotion { transaction.animation = nil }
    }
    .task {
      await store.loadRecentDocuments()
      await store.startBackend()
      await store.setDisplayTheme(isDark: colorScheme == .dark)
      if let startupURL {
        await store.open(startupURL)
      }
    }
    .onOpenURL { url in
      Task { await store.open(url) }
    }
    .onChange(of: colorScheme) { _, _ in
      Task { await store.setDisplayTheme(isDark: colorScheme == .dark) }
    }
    .sheet(isPresented: trustPromptBinding) {
      ExecutionTrustSheet(store: store)
    }
    .sheet(isPresented: $store.backendLogsPresented) {
      backendLogSheet
    }
    .sheet(isPresented: $store.recoverySourcePresented) {
      RecoverySourceView(store: store)
    }
  }

  private var notebookCanvas: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 16) {
          backendRecoveryBanner
          NotebookErrorBanner(store: store)
          ExternalFileBanner(store: store)
          saveMessageBanner
          openStateBanner
          ForEach(Array(store.document.cells.enumerated()), id: \.element.runtimeID) {
            index, cell in
            CellView(
              cell: cell,
              index: index + 1,
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
              },
              submitStdin: { text in
                Task { await store.submitStdin(cellID: cell.runtimeID, text: text) }
              },
              widgetStore: store.widgetValueStore,
              widgetsEnabled: store.interactiveWidgetsAllowed,
              kernelSessionID: store.document.kernelSessionID,
              submitWidgetValue: { objectID, value, sessionID in
                Task {
                  await store.submitWidgetValue(
                    objectID: objectID,
                    value: value,
                    expectedSessionID: sessionID
                  )
                }
              }
            )
            .id(cell.runtimeID)
          }
        }
        .frame(maxWidth: 1_100)
        .padding()
        .frame(maxWidth: .infinity)
      }
      .onChange(of: store.document.selectedCellID) { _, selected in
        guard let selected else { return }
        proxy.scrollTo(selected, anchor: .center)
      }
    }
    .background(Color(nsColor: reduceTransparency ? .windowBackgroundColor : .textBackgroundColor))
    .accessibilityLabel("Notebook canvas")
    .background(NotebookWindowLifecycleView(store: store))
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
        .accessibilityLabel(localizedUI("Document title: %@", documentTitle))
    }
    ToolbarItem {
      environmentMenu
        .help("Python Environment")
    }
    ToolbarItem {
      Label(localizedSessionStatus, systemImage: sessionIcon)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Kernel Status")
        .accessibilityValue(localizedSessionStatus)
    }
    ToolbarItemGroup {
      Button("Run All", systemImage: "play.fill") {
        Task { await store.requestRunAll() }
      }
      .disabled(!canRun)
      .help("Run All (⇧⌘↩)")
      .accessibilityLabel("Run All")
      if store.backendStatus == .ready {
        if store.forceRestartAvailable {
          Button(
            "Force Restart Kernel",
            systemImage: "exclamationmark.arrow.triangle.2.circlepath"
          ) {
            Task { await store.requestRestartKernel() }
          }
          .disabled(!store.sessionAllowsRestart)
        } else if store.sessionState == .running || store.sessionState == .interrupting {
          Button("Interrupt", systemImage: "stop.fill") {
            Task { await store.requestInterrupt() }
          }
          .disabled(!store.sessionAllowsInterrupt)
          .help("Interrupt (⌘.)")
          .accessibilityLabel("Interrupt")
        } else {
          Button("Restart Kernel", systemImage: "arrow.triangle.2.circlepath") {
            Task { await store.requestRestartKernel() }
          }
          .disabled(!store.sessionAllowsRestart)
          .help("Restart Kernel")
          .accessibilityLabel("Restart Kernel")
        }
      } else {
        Button("Restart Backend", systemImage: "arrow.clockwise") {
          Task { await store.startBackend() }
        }
      }
      Button("Toggle Inspector", systemImage: "sidebar.right") {
        store.inspectorPresented.toggle()
      }
      .help("Toggle Inspector (⌥⌘I)")
      .accessibilityLabel("Toggle Inspector")
    }
  }

  @ViewBuilder
  private var backendRecoveryBanner: some View {
    if store.backendRecoveryStopped {
      VStack(alignment: .leading, spacing: 8) {
        Label("Backend restart limit reached", systemImage: "exclamationmark.triangle.fill")
          .font(.headline)
        Text("Automatic restart stopped after three attempts in 60 seconds.")
          .foregroundStyle(.secondary)
        HStack {
          Button("Open Logs") { store.backendLogsPresented = true }
          Button("Restart Backend") { Task { await store.startBackend() } }
        }
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
  }

  private var backendLogSheet: some View {
    NotebookLogReviewView(store: store)
  }

  private var documentTitle: String {
    store.document.sourceURL?.lastPathComponent ?? "Untitled"
  }

  private var canRun: Bool {
    store.environmentAllowsExecutionRequest && store.backendStatus == .ready
      && store.sessionAllowsRun && store.documentAllowsExecution
  }

  private var sessionIcon: String {
    switch store.sessionState {
    case .running: "play.circle.fill"
    case .interrupting, .restarting, .starting: "progress.indicator"
    case .failed: "exclamationmark.circle.fill"
    case .idle: "checkmark.circle"
    case .notStarted, .closed: "circle"
    }
  }

  private var localizedSessionStatus: String {
    switch store.sessionState {
    case .notStarted: localizedUI("Not Started")
    case .starting: localizedUI("Starting")
    case .idle: localizedUI("Idle")
    case .running: localizedUI("Running")
    case .interrupting: localizedUI("Interrupting")
    case .restarting: localizedUI("Restarting")
    case .failed(let technicalDetail): "\(localizedUI("Failed")): \(technicalDetail)"
    case .closed: localizedUI("Closed")
    }
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
    case .runAndAdvance:
      guard canRun else { return }
      Task { await store.requestRunCell(cellID, advance: true) }
    case .runAndStay:
      guard canRun else { return }
      Task { await store.requestRunCell(cellID) }
    case .runAndInsert:
      guard canRun else { return }
      Task { await store.requestRunCell(cellID, insertBelow: true) }
    case .runAll:
      guard canRun else { return }
      Task { await store.requestRunAll() }
    case .interrupt:
      Task { await store.requestInterrupt() }
    }
  }

  private var trustPromptBinding: Binding<Bool> {
    Binding(
      get: { store.executionTrustPromptPresented },
      set: { if !$0 { store.cancelExecutionTrust() } }
    )
  }

  private var environmentMenu: some View {
    Menu {
      ForEach(store.environmentCandidates) { candidate in
        Button {
          Task { await store.selectPythonEnvironment(candidate) }
        } label: {
          Label(candidate.executableURL.path, systemImage: "terminal")
        }
      }
      if !store.environmentCandidates.isEmpty { Divider() }
      Button("Choose Python Executable…") {
        NotebookEnvironmentActions.chooseExecutable(for: store)
      }
      Button("Choose Working Directory…") {
        NotebookEnvironmentActions.chooseWorkingDirectory(for: store)
      }
    } label: {
      Label(environmentLabel, systemImage: "chevron.left.forwardslash.chevron.right")
    }
    .accessibilityLabel("Python Environment")
    .accessibilityValue(environmentLabel)
  }

  private var environmentLabel: String {
    switch store.environmentState {
    case .notConfigured: localizedUI("No Python Environment")
    case .selected: localizedUI("Python Environment · Not Inspected")
    case .checking: localizedUI("Checking Python…")
    case .invalid: localizedUI("Invalid Python Environment")
    case .needsWorkingDirectory(let details):
      localizedUI("Python %@ · Choose Folder", details.pythonVersion.description)
    case .ready(let details, _): "Python \(details.pythonVersion) · marimo \(details.marimoVersion)"
    }
  }

  private func move(_ cellID: UUID, offset: Int) {
    guard let index = store.document.cells.firstIndex(where: { $0.runtimeID == cellID }) else {
      return
    }
    Task { await store.send(.moveCell(cellID, to: index + offset)) }
  }

  @ViewBuilder
  private var saveMessageBanner: some View {
    if let message = store.saveMessage {
      HStack {
        Label(message, systemImage: "exclamationmark.circle")
        Spacer()
        Button("Dismiss", systemImage: "xmark") {
          store.dismissSaveMessage()
        }
        .labelStyle(.iconOnly)
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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
