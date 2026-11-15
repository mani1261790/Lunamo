import Foundation
import MarimoApplication
import MarimoDomain
import MarimoEditor
import MarimoEnvironment
import SwiftUI

public struct NotebookRootView: View {
  @ObservedObject var shortcutSettings = NotebookShortcutSettings.shared
  @ObservedObject var store: NotebookStore
  private let startupURL: URL?
  @State var sidebarPresented = true
  @StateObject var assistantConversation = NotebookAssistantConversation()
  @StateObject var terminalSession = NotebookTerminalSession()
  @State var terminalPresented = false
  @State private var cellFrames: [UUID: CGRect] = [:]
  @State private var collapsedHeadingCellIDs: Set<UUID> = []
  @State private var draggedCellID: UUID?
  @State private var reorderBoundary: Int?
  @State private var packageInstallConfirmationPresented = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.openSettings) var openSettings

  public init(store: NotebookStore, startupURL: URL? = nil) {
    self.store = store
    self.startupURL = startupURL
  }

  public var body: some View {
    NotebookWorkspaceLayout(
      sidebarPresented: sidebarPresented,
      assistantPresented: store.assistantPresented
    ) {
      VStack(spacing: 0) {
        HStack {
          Spacer()
          sidebarToggle
        }
        .padding(.leading, 84)
        .padding(.trailing, 12)
        .frame(height: 52)
        .background(NotebookWindowDragRegion())
        NotebookSidebarView(store: store)
      }
      .background { sidebarBackground }
    } editor: {
      VStack(spacing: 0) {
        notebookToolbar
          .padding(.leading, sidebarPresented ? 12 : 88)
          .padding(.trailing, 12)
          .frame(height: 52)
          .background(NotebookWindowDragRegion())
        notebookDetail
      }
      .background { editorBackground }
    } assistant: {
      NotebookAssistantView(store: store, conversation: assistantConversation)
        .background { sidebarBackground }
    }
    .ignoresSafeArea(.container, edges: .top)
    .frame(minWidth: 960, idealWidth: 1_320, minHeight: 640, idealHeight: 800)
    .transaction { transaction in
      if reduceMotion { transaction.animation = nil }
    }
    .task {
      await store.loadRecentDocuments()
      await store.startBackend()
      if startupURL == nil {
        await store.refreshPythonEnvironments()
        await store.refreshSidebarFiles()
      }
      await store.setDisplayTheme(isDark: colorScheme == .dark)
      if let startupURL {
        NotebookOpenActions.open(startupURL, store: store)
      }
    }
    .onOpenURL { url in
      NotebookOpenActions.open(url, store: store)
    }
    .onChange(of: colorScheme) { _, _ in
      Task { await store.setDisplayTheme(isDark: colorScheme == .dark) }
    }
    .onChange(of: store.document.documentID) { _, _ in
      assistantConversation.reset()
      collapsedHeadingCellIDs.removeAll()
      Task { await terminalSession.stop() }
    }
    .onChange(of: executionPresentation, initial: true) { _, state in
      NSApplication.shared.dockTile.badgeLabel = state.dockBadge
    }
    .onDisappear {
      NSApplication.shared.dockTile.badgeLabel = nil
      Task { await terminalSession.stop() }
    }
    .sheet(isPresented: trustPromptBinding) {
      ExecutionTrustSheet(store: store)
    }
    .sheet(isPresented: $store.backendLogsPresented) {
      NotebookLogReviewView(store: store)
    }
    .sheet(isPresented: $store.recoverySourcePresented) {
      RecoverySourceView(store: store)
    }
    .confirmationDialog(
      localizedUI("Install packages in the selected environment?"),
      isPresented: $packageInstallConfirmationPresented,
      titleVisibility: .visible
    ) {
      Button(localizedUI("Install %@", store.missingPackages.joined(separator: ", "))) {
        Task { await store.installPackages(store.missingPackages) }
      }
      Button(localizedUI("Cancel"), role: .cancel) {}
    } message: {
      Text(
        localizedUI(
          "Lunamo will create or reuse its shared environment unless this project is set to use a separate environment."
        ))
    }
  }

  @ViewBuilder
  private var notebookDetail: some View {
    if terminalPresented {
      NotebookTerminalSplit {
        notebookCanvas
      } terminal: {
        NotebookTerminalView(
          session: terminalSession,
          directoryURL: store.notebookDirectoryURL,
          pythonEnvironment: store.terminalPythonEnvironment,
          saveNotebook: { NotebookSaveActions.saveAs(store) },
          close: {
            terminalPresented = false
            Task { await terminalSession.stop() }
          }
        )
      }
    } else {
      notebookCanvas
    }
  }

  private var notebookCanvas: some View {
    let sectionRows = NotebookSectionLayout.visibleRows(
      cells: store.document.cells,
      collapsedHeadingCellIDs: collapsedHeadingCellIDs
    )

    return ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 0) {
          backendRecoveryBanner
          NotebookErrorBanner(store: store)
          ExternalFileBanner(store: store)
          saveMessageBanner
          openStateBanner
          executionSetupBanner
          packageSetupBanner(
            confirmInstall: { packageInstallConfirmationPresented = true })
          insertionBar(at: 0)
          ForEach(sectionRows) { row in
            let index = row.index
            let cell = row.cell
            CellView(
              cell: cell,
              index: index + 1,
              selected: store.document.selectedCellID == cell.runtimeID,
              focused: store.focusedCellID == cell.runtimeID,
              canRun: canRun,
              canInterrupt: store.sessionAllowsInterrupt,
              runDisabledHelp: runDisabledHelp,
              reorderDragChanged: updateReorderDrag,
              reorderDragEnded: finishReorderDrag,
              reportFrame: { id, frame in cellFrames[id] = frame },
              tracksReorderFrame: draggedCellID != nil,
              sectionHeadingLevel: row.headingLevel,
              sectionCollapsed: collapsedHeadingCellIDs.contains(cell.runtimeID),
              toggleSection: {
                toggleSection(cell.runtimeID)
              },
              attachToAssistant: {
                presentAssistant(for: cell, index: index + 1)
              },
              explainErrorWithAssistant: {
                presentAssistant(
                  for: cell, index: index + 1,
                  prompt: localizedUI("Explain this error and show me how to fix it"))
              },
              fixErrorWithAssistant: {
                presentAssistant(
                  for: cell, index: index + 1,
                  prompt: localizedUI(
                    "Fix this error. Return the complete corrected cell in one Python code block."))
              },
              askAssistant: { prompt, selection in
                presentAssistant(
                  for: cell, index: index + 1, prompt: prompt, selection: selection)
              },
              updateSelection: { selection in
                store.updateCodeSelection(cellID: cell.runtimeID, selection: selection)
              },
              requestCompletions: { source, line, column in
                await store.pythonCompletions(source: source, line: line, column: column)
              },
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
            .contextMenu {
              Menu("Assistant", systemImage: "sparkles") {
                Button("Explain Code", systemImage: "text.magnifyingglass") {
                  presentAssistant(
                    for: cell, index: index + 1,
                    prompt: localizedUI("Explain this code clearly."),
                    selection: store.codeSelections[cell.runtimeID])
                }
                Button("Fix or Improve Code", systemImage: "wrench.and.screwdriver") {
                  presentAssistant(
                    for: cell, index: index + 1,
                    prompt: localizedUI(
                      "Fix or improve this code. Return the complete replacement in one Python code block."
                    ),
                    selection: store.codeSelections[cell.runtimeID])
                }
                Button("Generate Tests", systemImage: "checkmark.seal") {
                  presentAssistant(
                    for: cell, index: index + 1,
                    prompt: localizedUI(
                      "Generate useful tests for this code and return them in one Python code block."
                    ),
                    selection: store.codeSelections[cell.runtimeID])
                }
              }
              Divider()
              Button("Duplicate Cell", systemImage: "square.on.square") {
                Task { await store.send(.duplicateCell(cell.runtimeID)) }
              }
              Button("Delete Cell", systemImage: "trash", role: .destructive) {
                Task { await store.send(.deleteCell(cell.runtimeID)) }
              }
            }
            insertionBar(at: index + 1)
          }
        }
        .frame(maxWidth: 1_100)
        .animation(
          reduceMotion ? nil : .snappy(duration: 0.2),
          value: store.document.cells.map(\.runtimeID)
        )
        .animation(
          reduceMotion ? nil : .snappy(duration: 0.22),
          value: collapsedHeadingCellIDs
        )
        .padding()
        .frame(maxWidth: .infinity)
      }
      .coordinateSpace(name: "notebookCanvas")
      .onChange(of: store.document.selectedCellID) { _, selected in
        guard let selected else { return }
        proxy.scrollTo(selected, anchor: .center)
      }
    }
    .accessibilityLabel("Notebook canvas")
    .background(NotebookWindowLifecycleView(store: store))
  }

  @ViewBuilder
  private var editorBackground: some View {
    if reduceTransparency {
      Color(nsColor: .windowBackgroundColor)
    } else {
      NotebookWindowMaterial(material: .contentBackground)
        .overlay(Color(nsColor: .windowBackgroundColor).opacity(0.25))
        .allowsHitTesting(false)
    }
  }

  @ViewBuilder
  private var sidebarBackground: some View {
    if reduceTransparency {
      Color(nsColor: .windowBackgroundColor)
    } else {
      NotebookWindowMaterial()
        .allowsHitTesting(false)
    }
  }

  private func handle(_ command: CodeEditorCommand, cellID: UUID) {
    switch command {
    case .openInlineAssistant:
      break
    case .askAssistant:
      break
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

  private func move(_ cellID: UUID, offset: Int) {
    guard let index = store.document.cells.firstIndex(where: { $0.runtimeID == cellID }) else {
      return
    }
    Task { await store.send(.moveCell(cellID, to: index + offset)) }
  }

  private func toggleSection(_ cellID: UUID) {
    let willCollapse = !collapsedHeadingCellIDs.contains(cellID)
    if willCollapse {
      collapsedHeadingCellIDs.insert(cellID)
    } else {
      collapsedHeadingCellIDs.remove(cellID)
    }

    guard willCollapse, let selectedCellID = store.document.selectedCellID else { return }
    let visibleCellIDs = Set(
      NotebookSectionLayout.visibleRows(
        cells: store.document.cells,
        collapsedHeadingCellIDs: collapsedHeadingCellIDs
      ).map(\.id)
    )
    guard !visibleCellIDs.contains(selectedCellID) else { return }
    Task { await store.send(.selectCell(cellID)) }
  }

  private func insertionBar(at position: Int) -> some View {
    CellInsertionBar(
      position: position,
      insertCode: {
        Task { await store.send(.insertCellAt(position)) }
      },
      insertText: {
        Task { await store.send(.insertTextCellAt(position)) }
      },
      reorderTargeted: draggedCellID != nil && reorderBoundary == position
    )
  }

  private func updateReorderDrag(_ cellID: UUID, _ locationY: CGFloat) {
    if draggedCellID == nil { cellFrames.removeAll(keepingCapacity: true) }
    draggedCellID = cellID
    reorderBoundary = insertionBoundary(at: locationY, excluding: cellID)
  }

  private func finishReorderDrag(_ cellID: UUID, _ locationY: CGFloat) {
    let destination = insertionBoundary(at: locationY, excluding: cellID)
    draggedCellID = nil
    reorderBoundary = nil
    cellFrames.removeAll(keepingCapacity: true)
    reorderCell(cellID, destination)
  }

  private func insertionBoundary(at locationY: CGFloat, excluding cellID: UUID) -> Int {
    for (index, cell) in store.document.cells.enumerated() where cell.runtimeID != cellID {
      guard let frame = cellFrames[cell.runtimeID] else { continue }
      if locationY < frame.midY { return index }
    }
    return store.document.cells.count
  }

  private func reorderCell(_ cellID: UUID, _ destination: Int) {
    guard let source = store.document.cells.firstIndex(where: { $0.runtimeID == cellID }) else {
      return
    }
    guard
      let adjustedDestination = CellReorderPosition.destination(
        source: source, insertionBoundary: destination, count: store.document.cells.count
      )
    else { return }
    Task { await store.send(.moveCell(cellID, to: adjustedDestination)) }
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
