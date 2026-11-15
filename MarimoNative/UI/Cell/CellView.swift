import AppKit
import MarimoApplication
import MarimoDomain
import MarimoEditor
import MarimoOutput
import MarimoWidgets
import SwiftUI

public struct CellView: View {
  @ObservedObject var shortcutSettings = NotebookShortcutSettings.shared
  let cell: NotebookCellState
  let index: Int
  private let selected: Bool
  private let focused: Bool
  let canRun: Bool
  let canInterrupt: Bool
  let runDisabledHelp: String
  private let reorderDragChanged: (UUID, CGFloat) -> Void
  private let reorderDragEnded: (UUID, CGFloat) -> Void
  private let reportFrame: (UUID, CGRect) -> Void
  private let tracksReorderFrame: Bool
  private let sectionHeadingLevel: Int?
  private let sectionCollapsed: Bool
  private let toggleSection: () -> Void
  private let attachToAssistant: () -> Void
  private let explainErrorWithAssistant: () -> Void
  private let fixErrorWithAssistant: () -> Void
  let askAssistant: (String, String?) -> Void
  let updateSelection: @MainActor @Sendable (String?) -> Void
  let requestCompletions: @MainActor @Sendable (String, Int, Int) async -> [PythonCompletionItem]
  private let send: @MainActor @Sendable (NotebookIntent) -> Void
  let focusEditor: @MainActor @Sendable () -> Void
  let command: @MainActor @Sendable (CodeEditorCommand) -> Void
  let submitStdin: @MainActor @Sendable (String) -> Void
  private let widgetStore: WidgetValueStore
  private let widgetsEnabled: Bool
  private let kernelSessionID: String?
  private let submitWidgetValue: @MainActor @Sendable (String, Double, String) -> Void

  @State private var editorHeight: CGFloat = 72
  @State private var internallyScrollable = false
  @State var stdinText = ""
  @State private var editingMarkdown: Bool
  @State var cellHovered = false
  @State var editorHovered = false
  @State var cursorOwner = UUID()
  @State var actionControlsHovered = false
  @State var reorderCursorActive = false
  @GestureState private var reordering = false
  @GestureState private var reorderOffset: CGSize = .zero
  @FocusState private var markdownEditorFocused: Bool
  @State var inlineAssistantPresented = false
  @State var inlineAssistantDraft = ""
  @State var selectedCodeText: String?
  @State var executionControlHovered = false
  @State private var sectionToggleHovered = false
  @FocusState var inlineAssistantFocused: Bool

  public init(
    cell: NotebookCellState,
    index: Int = 1,
    selected: Bool,
    focused: Bool,
    canRun: Bool,
    canInterrupt: Bool = false,
    runDisabledHelp: String = "Select a valid Python environment to run",
    reorderDragChanged: @escaping (UUID, CGFloat) -> Void = { _, _ in },
    reorderDragEnded: @escaping (UUID, CGFloat) -> Void = { _, _ in },
    reportFrame: @escaping (UUID, CGRect) -> Void = { _, _ in },
    tracksReorderFrame: Bool = false,
    sectionHeadingLevel: Int? = nil,
    sectionCollapsed: Bool = false,
    toggleSection: @escaping () -> Void = {},
    attachToAssistant: @escaping () -> Void = {},
    explainErrorWithAssistant: @escaping () -> Void = {},
    fixErrorWithAssistant: @escaping () -> Void = {},
    askAssistant: @escaping (String, String?) -> Void = { _, _ in },
    updateSelection: @escaping @MainActor @Sendable (String?) -> Void = { _ in },
    requestCompletions:
      @escaping @MainActor @Sendable (String, Int, Int) async
      -> [PythonCompletionItem] = { _, _, _ in [] },
    send: @escaping @MainActor @Sendable (NotebookIntent) -> Void,
    focusEditor: @escaping @MainActor @Sendable () -> Void,
    command: @escaping @MainActor @Sendable (CodeEditorCommand) -> Void,
    submitStdin: @escaping @MainActor @Sendable (String) -> Void = { _ in },
    widgetStore: WidgetValueStore,
    widgetsEnabled: Bool,
    kernelSessionID: String?,
    submitWidgetValue: @escaping @MainActor @Sendable (String, Double, String) -> Void
  ) {
    self.cell = cell
    self.index = index
    self.selected = selected
    self.focused = focused
    self.canRun = canRun
    self.canInterrupt = canInterrupt
    self.runDisabledHelp = runDisabledHelp
    self.reorderDragChanged = reorderDragChanged
    self.reorderDragEnded = reorderDragEnded
    self.reportFrame = reportFrame
    self.tracksReorderFrame = tracksReorderFrame
    self.sectionHeadingLevel = sectionHeadingLevel
    self.sectionCollapsed = sectionCollapsed
    self.toggleSection = toggleSection
    self.attachToAssistant = attachToAssistant
    self.explainErrorWithAssistant = explainErrorWithAssistant
    self.fixErrorWithAssistant = fixErrorWithAssistant
    self.askAssistant = askAssistant
    self.updateSelection = updateSelection
    self.requestCompletions = requestCompletions
    self.send = send
    self.focusEditor = focusEditor
    self.command = command
    self.submitStdin = submitStdin
    self.widgetStore = widgetStore
    self.widgetsEnabled = widgetsEnabled
    self.kernelSessionID = kernelSessionID
    self.submitWidgetValue = submitWidgetValue
    _editingMarkdown = State(initialValue: cell.editor.markdown?.isEmpty == true)
  }

  public var body: some View {
    Group {
      if let markdown = cell.editor.markdown {
        textCell(markdown: markdown)
      } else {
        codeCell
      }
    }
    .padding(.vertical, 4)
    .background {
      if cell.editor.markdown == nil {
        RoundedRectangle(cornerRadius: 12)
          .fill(.quaternary.opacity(0.35))
      }
    }
    .reportNotebookFrame(
      when: tracksReorderFrame,
      cellID: cell.runtimeID,
      report: reportFrame
    )
    .offset(y: reorderOffset.height)
    .zIndex(reordering ? 20 : 0)
    .shadow(color: reordering ? .black.opacity(0.2) : .clear, radius: 18, y: 8)
    .scaleEffect(reordering ? 0.995 : 1)
    .contentShape(Rectangle())
    .simultaneousGesture(
      TapGesture().onEnded {
        send(.selectCell(cell.runtimeID))
      }
    )
    .simultaneousGesture(reorderGesture)
    .onHover { hovering in
      cellHovered = hovering
      if !hovering {
        editorHovered = false
        actionControlsHovered = false
      }
      updateHoverCursor()
    }
    .onChange(of: reordering) { _, active in
      updateReorderCursor(active: active)
    }
    .onDisappear {
      cellHovered = false
      actionControlsHovered = false
      restoreReorderCursor()
      restoreHoverCursor()
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(localizedUI("Cell %ld, %@", index, cell.name))
    .accessibilityValue(statusLabel(cell.runtime.status))
  }

  private var codeCell: some View {
    HStack(alignment: .top, spacing: 10) {
      executionRail

      VStack(alignment: .leading, spacing: 10) {
        CodeEditorView(
          text: cell.code,
          isFocused: focused,
          onTextChange: { text, hasMarkedText in
            send(
              .updateComposedCode(
                cellID: cell.runtimeID,
                code: text,
                hasMarkedText: hasMarkedText
              )
            )
          },
          onFocus: focusEditor,
          onCommand: handleCodeEditorCommand,
          onSelectionChange: { selection in
            selectedCodeText = selection
            updateSelection(selection)
          },
          completionProvider: requestCompletions,
          onHeightChange: { height, scrollable in
            editorHeight = height
            internallyScrollable = scrollable
          },
          accessibilityLabel: localizedUI("Python code editor")
        )
        .frame(height: editorHeight)
        .background(
          Color(nsColor: .controlBackgroundColor),
          in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(
              Color(nsColor: selected ? .controlAccentColor : .separatorColor),
              lineWidth: selected ? 1.5 : 1
            )
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
          if cellHovered {
            hoverActionBar
              .padding(.trailing, 8)
              .offset(y: -14)
              .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
          }
        }
        .overlay(alignment: .topTrailing) {
          if internallyScrollable {
            Label("Scrollable editor", systemImage: "arrow.up.and.down")
              .labelStyle(.iconOnly)
              .foregroundStyle(.secondary)
              .padding(6)
              .accessibilityLabel("This cell has its own vertical scroll area")
          }
        }
        .overlay {
          if internallyScrollable {
            VStack(spacing: 0) {
              Divider()
              Spacer()
              Divider()
            }
            .allowsHitTesting(false)
          }
        }
        .onHover { hovering in
          editorHovered = hovering
          updateHoverCursor()
        }

        if inlineAssistantPresented { inlineAssistantPrompt }

        codeCellRuntimeContent
      }
    }
    .padding(.trailing, 16)
  }

  @ViewBuilder
  private var codeCellRuntimeContent: some View {
    if let prompt = cell.runtime.stdinPrompt {
      stdinField(prompt)
    }

    if let output = cell.runtime.output,
      OutputVisibility.hasRenderableContent(output)
    {
      OutputView(
        output: output,
        stale: cell.runtime.stale,
        running: cell.runtime.status == .running,
        widgetStore: widgetStore,
        widgetCellID: cell.runtimeID.uuidString,
        widgetsEnabled: widgetsEnabled,
        kernelSessionID: kernelSessionID,
        sendWidgetValue: submitWidgetValue
      )
    }

    ForEach(Array(cell.runtime.console.enumerated()), id: \.offset) { _, item in
      if item.channel != .stdin,
        OutputVisibility.hasRenderableContent(item)
      {
        OutputView(
          output: item,
          widgetStore: widgetStore,
          widgetCellID: cell.runtimeID.uuidString,
          widgetsEnabled: widgetsEnabled,
          kernelSessionID: kernelSessionID,
          sendWidgetValue: submitWidgetValue
        )
      }
    }

    if NotebookRuntimeErrorContext.runtimeErrorContext(for: cell) != nil {
      HStack(spacing: 8) {
        Button(action: explainErrorWithAssistant) {
          Label(localizedUI("Explain Error"), systemImage: "sparkles")
        }
        Button(action: fixErrorWithAssistant) {
          Label(localizedUI("Suggest Fix"), systemImage: "wrench.and.screwdriver")
        }
      }
      .buttonStyle(.bordered)
      .buttonBorderShape(.capsule)
      .controlSize(.small)
      .onHover { hovering in
        actionControlsHovered = hovering
        updateHoverCursor()
      }
      .onDisappear {
        actionControlsHovered = false
        updateHoverCursor()
      }
    }
  }

  private func textCell(markdown: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if editingMarkdown {
        TextEditor(
          text: Binding(
            get: { cell.editor.markdown ?? "" },
            set: { send(.updateMarkdown(cellID: cell.runtimeID, markdown: $0)) }
          )
        )
        .font(.body.monospaced())
        .focused($markdownEditorFocused)
        .scrollContentBackground(.hidden)
        .frame(minHeight: 140, maxHeight: 320)
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
          RoundedRectangle(cornerRadius: 10)
            .stroke(Color.accentColor.opacity(0.8), lineWidth: 1.5)
            .allowsHitTesting(false)
        }
        .accessibilityLabel(localizedUI("Markdown text editor"))
        .onTapGesture { focusEditor() }
        .onHover { hovering in
          editorHovered = hovering
          updateHoverCursor()
        }
        .onAppear {
          Task { @MainActor in
            await Task.yield()
            markdownEditorFocused = true
            focusEditor()
          }
        }
      } else {
        MarkdownDocumentView(source: markdown)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .padding(.horizontal, 12)
          .padding(.vertical, 2)
          .contentShape(Rectangle())
          .highPriorityGesture(
            TapGesture(count: 2).onEnded {
              editingMarkdown = true
              Task { @MainActor in
                await Task.yield()
                markdownEditorFocused = true
                focusEditor()
              }
            }
          )
      }
    }
    .padding(.leading, 54)
    .overlay(alignment: .topLeading) {
      if sectionHeadingLevel != nil, !editingMarkdown {
        sectionDisclosureButton
          .padding(.leading, 8)
          .padding(.top, 2)
      }
    }
    .overlay(alignment: .topTrailing) {
      if cellHovered {
        hoverActionBar
          .padding(.trailing, 8)
          .offset(y: -14)
          .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
      }
    }
    .onChange(of: markdownEditorFocused) { _, isFocused in
      if !isFocused && editingMarkdown {
        editingMarkdown = false
      }
    }
    .animation(.easeOut(duration: 0.14), value: cellHovered)
  }

  private var sectionDisclosureButton: some View {
    Button(action: toggleSection) {
      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .rotationEffect(.degrees(sectionCollapsed ? 0 : 90))
        .frame(width: 28, height: 28)
        .contentShape(Circle())
        .background(
          sectionToggleHovered ? Color.primary.opacity(0.08) : .clear,
          in: Circle()
        )
    }
    .buttonStyle(.plain)
    .onHover { sectionToggleHovered = $0 }
    .animation(.easeOut(duration: 0.14), value: sectionCollapsed)
    .animation(.easeOut(duration: 0.12), value: sectionToggleHovered)
    .help(localizedUI(sectionCollapsed ? "Expand Section" : "Collapse Section"))
    .accessibilityLabel(localizedUI(sectionCollapsed ? "Expand Section" : "Collapse Section"))
  }

  private var hoverActionBar: some View {
    HStack(spacing: 6) {
      Button("Attach Cell to Assistant", systemImage: "sparkles", action: attachToAssistant)
        .help("Attach this cell to the Assistant conversation")
      Button("Duplicate Cell", systemImage: "square.on.square") {
        send(.duplicateCell(cell.runtimeID))
      }
      Button("Delete Cell", systemImage: "trash") {
        send(.deleteCell(cell.runtimeID))
      }
    }
    .labelStyle(.iconOnly)
    .buttonStyle(.borderless)
    .controlSize(.small)
    .padding(.horizontal, 9)
    .frame(height: 28)
    .background(.regularMaterial, in: Capsule(style: .continuous))
    .overlay {
      Capsule(style: .continuous)
        .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
        .allowsHitTesting(false)
    }
    .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
    .onHover { hovering in
      actionControlsHovered = hovering
      updateHoverCursor()
    }
    .onDisappear {
      actionControlsHovered = false
      updateHoverCursor()
    }
  }

  private var reorderGesture: some Gesture {
    LongPressGesture(minimumDuration: 0.16, maximumDistance: 8)
      .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("notebookCanvas")))
      .updating($reorderOffset) { value, state, _ in
        guard case .second(true, let drag?) = value else { return }
        state = drag.translation
      }
      .updating($reordering) { value, state, _ in
        guard case .second(true, .some) = value else { return }
        state = true
      }
      .onChanged { value in
        guard case .second(true, let drag?) = value else { return }
        reorderDragChanged(cell.runtimeID, drag.location.y)
      }
      .onEnded { value in
        guard case .second(true, let drag?) = value else { return }
        reorderDragEnded(cell.runtimeID, drag.location.y)
      }
  }

}

extension View {
  @ViewBuilder
  fileprivate func reportNotebookFrame(
    when enabled: Bool,
    cellID: UUID,
    report: @escaping (UUID, CGRect) -> Void
  ) -> some View {
    if enabled {
      onGeometryChange(for: CGRect.self) {
        $0.frame(in: .named("notebookCanvas"))
      } action: {
        report(cellID, $0)
      }
    } else {
      self
    }
  }
}
