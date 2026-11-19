import AppKit
import MarimoApplication
import MarimoEditor
import SwiftUI

public struct NotebookMenuCommands: Commands {
  @ObservedObject private var shortcuts = NotebookShortcutSettings.shared
  @ObservedObject private var store: NotebookStore

  public init(store: NotebookStore) {
    self.store = store
  }

  public var body: some Commands {
    SidebarCommands()

    CommandGroup(after: .appInfo) {
      Button("Licenses…") {
        guard let url = Bundle.main.resourceURL?.appending(path: "Licenses/index.html") else { return }
        NSWorkspace.shared.open(url)
      }
    }

    CommandGroup(replacing: .newItem) {
      Button("Open Notebook…") {
        NotebookOpenActions.open(store)
      }
      .keyboardShortcut("o", modifiers: [.command])
      if !store.recentDocuments.isEmpty {
        Menu("Open Recent") {
          ForEach(store.recentDocuments, id: \.self) { url in
            Button(url.lastPathComponent) { Task { await store.open(url) } }
          }
        }
      }
    }

    CommandMenu("Notebook") {
      Button("Run Cell and Advance") {
        guard let cellID = store.document.selectedCellID else { return }
        Task { await store.requestRunCell(cellID, advance: true) }
      }
      .keyboardShortcut(shortcuts.shortcut(for: .runAndAdvance)?.toSwiftUI)
      .disabled(!canRunSelectedCell)
      Button("Run Cell") {
        guard let cellID = store.document.selectedCellID else { return }
        Task { await store.requestRunCell(cellID) }
      }
      .keyboardShortcut(shortcuts.shortcut(for: .runAndStay)?.toSwiftUI)
      .disabled(!canRunSelectedCell)
      Button("Run Cell and Insert Below") {
        guard let cellID = store.document.selectedCellID else { return }
        Task { await store.requestRunCell(cellID, insertBelow: true) }
      }
      .keyboardShortcut(shortcuts.shortcut(for: .runAndInsert)?.toSwiftUI)
      .disabled(!canRunSelectedCell)
      Button("Run All") {
        Task { await store.requestRunAll() }
      }
      .keyboardShortcut(shortcuts.shortcut(for: .runAll)?.toSwiftUI)
      .disabled(!canRun)
      Button("Interrupt") {
        Task { await store.requestInterrupt() }
      }
      .keyboardShortcut(shortcuts.shortcut(for: .interrupt)?.toSwiftUI)
      .disabled(!store.sessionAllowsInterrupt)

      Button("Find in Selected Cell") {
        findInSelectedCell()
      }
      .keyboardShortcut("f", modifiers: [.command])
      .disabled(store.document.selectedCellID == nil)
      Button(store.forceRestartAvailable ? "Force Restart Kernel" : "Restart Kernel") {
        Task { await store.requestRestartKernel() }
      }
      .disabled(!store.sessionAllowsRestart)

      Divider()

      Button("Focus Selected Cell Editor") {
        if let cellID = store.document.selectedCellID {
          store.focusEditor(cellID)
        }
      }
      .keyboardShortcut(.return, modifiers: [])
      .disabled(store.document.selectedCellID == nil || store.focusedCellID != nil)
      Button("Leave Cell Editor") {
        store.leaveEditor()
      }
      .keyboardShortcut(.escape, modifiers: [])
      .disabled(store.focusedCellID == nil)

      Divider()

      Button("Move Cell Up") {
        moveSelectedCell(by: -1)
      }
      .keyboardShortcut(shortcuts.shortcut(for: .moveUp)?.toSwiftUI)
      .disabled(!canMoveSelectedCell(by: -1))
      Button("Move Cell Down") {
        moveSelectedCell(by: 1)
      }
      .keyboardShortcut(shortcuts.shortcut(for: .moveDown)?.toSwiftUI)
      .disabled(!canMoveSelectedCell(by: 1))
      Button("Delete Selected Cell") {
        guard let cellID = store.document.selectedCellID else { return }
        Task { await store.send(.deleteCell(cellID)) }
      }
      .keyboardShortcut(.delete, modifiers: [.command, .shift])
      .disabled(store.document.selectedCellID == nil || store.focusedCellID != nil)

      Divider()

      Button("Toggle Assistant") {
        store.assistantPresented.toggle()
      }
      .keyboardShortcut(shortcuts.shortcut(for: .toggleAssistant)?.toSwiftUI)
    }

    CommandMenu("Export") {
      Button("Export HTML…") { NotebookExportActions.present(.html, store: store) }
        .disabled(!store.exportAllowed)
      Button("Export ipynb…") { NotebookExportActions.present(.ipynb, store: store) }
        .disabled(!store.exportAllowed)
      Button("Export Markdown…") { NotebookExportActions.present(.markdown, store: store) }
        .disabled(!store.exportAllowed)
      Divider()
      Button("Open Logs…") { Task { await store.prepareLogReview() } }
    }

    CommandGroup(after: .saveItem) {
      Button("Save Notebook") {
        NotebookSaveActions.save(store)
      }
      .keyboardShortcut("s", modifiers: [.command])
      .disabled(store.saveConflictURL != nil)
      Button("Save Notebook As…") {
        NotebookSaveActions.saveAs(store)
      }
      .keyboardShortcut("s", modifiers: [.command, .shift])
    }
  }

  private func canMoveSelectedCell(by offset: Int) -> Bool {
    guard let selected = store.document.selectedCellID,
      let index = store.document.cells.firstIndex(where: { $0.runtimeID == selected })
    else { return false }
    return store.document.cells.indices.contains(index + offset)
  }

  private var canRun: Bool {
    store.backendStatus == .ready && store.environmentAllowsExecutionRequest
      && store.sessionAllowsRun && store.documentAllowsExecution
  }

  private var canRunSelectedCell: Bool {
    canRun && store.document.selectedCellID != nil
  }

  private func moveSelectedCell(by offset: Int) {
    guard let selected = store.document.selectedCellID,
      let index = store.document.cells.firstIndex(where: { $0.runtimeID == selected })
    else { return }
    Task { await store.send(.moveCell(selected, to: index + offset)) }
  }

  private func findInSelectedCell() {
    guard let selected = store.document.selectedCellID else { return }
    store.focusEditor(selected)
    Task { @MainActor in
      await Task.yield()
      let sender = NSMenuItem()
      sender.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
      NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: sender)
    }
  }
}
