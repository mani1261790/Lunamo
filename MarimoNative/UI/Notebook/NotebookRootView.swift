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
    .sheet(isPresented: trustPromptBinding) {
      ExecutionTrustSheet(store: store)
    }
    .sheet(isPresented: $store.backendLogsPresented) {
      backendLogSheet
    }
  }

  private var notebookCanvas: some View {
    ScrollView {
      LazyVStack(spacing: 16) {
        backendRecoveryBanner
        saveConflictBanner
        saveMessageBanner
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
        }
      }
      .frame(maxWidth: 1_100)
      .padding()
      .frame(maxWidth: .infinity)
    }
    .background(Color(nsColor: .textBackgroundColor))
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
        .accessibilityLabel("Document title: \(documentTitle)")
    }
    ToolbarItem {
      environmentMenu
        .help("Python Environment")
    }
    ToolbarItem {
      Label(backendLabel, systemImage: backendIcon)
        .foregroundStyle(.secondary)
        .accessibilityValue(backendLabel)
    }
    ToolbarItemGroup {
      Button("Run All", systemImage: "play.fill") {
        Task { await store.requestRunAll() }
      }
      .disabled(!canRun)
      .help("Run All (⇧⌘↩)")
      if store.backendStatus == .ready {
        if store.forceRestartAvailable {
          Button(
            "Force Restart Kernel",
            systemImage: "exclamationmark.arrow.triangle.2.circlepath"
          ) {
            Task { await store.requestRestartKernel() }
          }
          .disabled(!store.sessionAllowsRestart)
        } else {
          Button("Interrupt", systemImage: "stop.fill") {
            Task { await store.requestInterrupt() }
          }
          .disabled(!store.sessionAllowsInterrupt)
          .help("Interrupt (⌘.)")
        }
        Button("Restart Kernel", systemImage: "arrow.triangle.2.circlepath") {
          Task { await store.requestRestartKernel() }
        }
        .disabled(!store.sessionAllowsRestart)
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
    NavigationStack {
      TextEditor(
        text: .constant(
          store.backendLogs.isEmpty
            ? "No sidecar stderr was captured." : store.backendLogs.joined(separator: "\n")
        )
      )
      .font(.system(.body, design: .monospaced))
      .padding()
      .navigationTitle("Backend Logs")
      .toolbar {
        Button("Done") { store.backendLogsPresented = false }
      }
    }
    .frame(minWidth: 640, minHeight: 420)
  }

  private var inspector: some View {
    Form {
      Section("Session") {
        LabeledContent("Backend", value: backendLabel)
        LabeledContent("Kernel", value: store.sessionStatusLabel)
        environmentInspector
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
    store.environmentAllowsExecutionRequest && store.backendStatus == .ready
      && store.sessionAllowsRun
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

  @ViewBuilder
  private var environmentInspector: some View {
    switch store.environmentState {
    case .notConfigured:
      LabeledContent("Environment", value: "Not Configured")
    case .selected(let candidate, let workingDirectory):
      LabeledContent("Environment", value: candidate.kind.displayName)
      LabeledContent("Executable", value: candidate.executableURL.path)
      LabeledContent("Preflight", value: "Runs on first execution")
      if let workingDirectory {
        LabeledContent("Working Directory", value: workingDirectory.path)
      }
    case .checking(let candidate):
      LabeledContent("Environment", value: "Checking \(candidate.executableURL.lastPathComponent)…")
    case .invalid(let candidate, let failure):
      LabeledContent("Environment", value: "Invalid")
      LabeledContent("Executable", value: candidate.executableURL.path)
      Text(failure.userMessage).foregroundStyle(.red)
    case .needsWorkingDirectory(let details):
      environmentDetails(details)
      LabeledContent("Working Directory", value: "Required before first run")
    case .ready(let details, let workingDirectory):
      environmentDetails(details)
      LabeledContent("Working Directory", value: workingDirectory.path)
      LabeledContent("Execution Trust", value: store.executionAuthorizationLabel)
    }
  }

  @ViewBuilder
  private func environmentDetails(_ details: PythonEnvironmentDetails) -> some View {
    LabeledContent("Environment", value: details.kind.displayName)
    LabeledContent("Selected Executable", value: details.executableURL.path)
    LabeledContent("Real Executable", value: details.realExecutableURL.path)
    LabeledContent("Python", value: details.pythonVersion.description)
    LabeledContent("Architecture", value: details.architecture)
    LabeledContent("marimo", value: details.marimoVersion)
    LabeledContent("marimo Module", value: details.marimoModuleURL.path)
  }

  private var environmentLabel: String {
    switch store.environmentState {
    case .notConfigured: "No Python Environment"
    case .selected: "Python Environment · Not Inspected"
    case .checking: "Checking Python…"
    case .invalid: "Invalid Python Environment"
    case .needsWorkingDirectory(let details): "Python \(details.pythonVersion) · Choose Folder"
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
  private var saveConflictBanner: some View {
    if let target = store.saveConflictURL {
      VStack(alignment: .leading, spacing: 8) {
        Label("File changed on disk", systemImage: "exclamationmark.triangle")
          .font(.headline)
        Text(target.lastPathComponent)
          .foregroundStyle(.secondary)
        HStack {
          Button("Reload from Disk") {
            Task { await store.reloadConflictedDocument() }
          }
          Button("Save Local Copy") {
            NotebookSaveActions.saveAs(store)
          }
          Button("Cancel") {
            store.cancelSaveConflict()
          }
        }
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
      .accessibilityElement(children: .contain)
    }
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
