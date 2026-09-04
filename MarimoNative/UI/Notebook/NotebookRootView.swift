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
  @State private var assistantPresented = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.openSettings) private var openSettings

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
    .sheet(isPresented: $assistantPresented) {
      NotebookAssistantView(store: store)
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
          executionSetupBanner
          insertionBar(at: 0)
          ForEach(Array(store.document.cells.enumerated()), id: \.element.runtimeID) {
            index, cell in
            CellView(
              cell: cell,
              index: index + 1,
              selected: store.document.selectedCellID == cell.runtimeID,
              focused: store.focusedCellID == cell.runtimeID,
              canRun: canRun,
              canMoveDown: index < store.document.cells.count - 1,
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
            insertionBar(at: index + 1)
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
    ToolbarItem {
      environmentMenu
        .help("Python Environment")
    }
    ToolbarItemGroup {
      Button {
        Task { await store.requestRunAll() }
      } label: {
        Label("Run All", systemImage: "play.fill")
          .labelStyle(.titleAndIcon)
      }
      .buttonStyle(.borderedProminent)
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
    ToolbarItem(placement: .primaryAction) {
      Button("Notebook Assistant", systemImage: "sparkles") {
        assistantPresented = true
      }
      .help("On-device Notebook Assistant")
      .accessibilityLabel("Notebook Assistant")
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
      Image(systemName: "terminal")
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

  @ViewBuilder
  private var executionSetupBanner: some View {
    switch store.environmentState {
    case .ready:
      EmptyView()
    case .checking:
      HStack(spacing: 10) {
        ProgressView().controlSize(.small)
        Text("Checking Python…")
        Spacer()
        Button("Settings…") { openSettings() }
      }
      .executionSetupBannerStyle()
    case .notConfigured:
      environmentGuidance(
        title: "Choose a Python environment",
        message: "Select the Python installation and folder that will run this notebook."
      )
    case .selected:
      environmentGuidance(
        title: "Python has not been checked",
        message: "The first Run checks Python and marimo, then asks before executing code."
      )
    case .needsWorkingDirectory:
      environmentGuidance(
        title: "Choose a working folder",
        message: "Python is valid. Select the folder used when this notebook runs."
      )
    case .invalid(_, let failure):
      environmentGuidance(title: "Python cannot run this notebook", message: failure.userMessage)
    }
  }

  private func environmentGuidance(title: String, message: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "terminal")
        .font(.title3)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.headline)
        Text(message).font(.callout).foregroundStyle(.secondary)
      }
      Spacer()
      Button("Settings…") { openSettings() }
    }
    .executionSetupBannerStyle()
  }

  private func move(_ cellID: UUID, offset: Int) {
    guard let index = store.document.cells.firstIndex(where: { $0.runtimeID == cellID }) else {
      return
    }
    Task { await store.send(.moveCell(cellID, to: index + offset)) }
  }

  private func insertionBar(at position: Int) -> some View {
    CellInsertionBar(
      position: position,
      insertCode: {
        Task { await store.send(.insertCellAt(position)) }
      },
      moveCell: { cellID, destination in
        guard let source = store.document.cells.firstIndex(where: { $0.runtimeID == cellID }) else {
          return
        }
        let adjustedDestination = source < destination ? destination - 1 : destination
        Task { await store.send(.moveCell(cellID, to: adjustedDestination)) }
      }
    )
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

extension View {
  fileprivate func executionSetupBannerStyle() -> some View {
    padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}
