import AppKit
import MarimoDomain
import MarimoOutput
import MarimoWebFallback
import MarimoWidgets
import SwiftUI

public struct OutputView: View {
  private let output: MarimoOutput
  private let stale: Bool
  private let running: Bool
  private let widgetStore: WidgetValueStore?
  private let widgetCellID: String?
  private let widgetsEnabled: Bool
  private let kernelSessionID: String?
  private let sendWidgetValue: @MainActor @Sendable (String, Double, String) -> Void
  @State private var prepared: PreparedOutput?

  public init(
    output: MarimoOutput,
    stale: Bool = false,
    running: Bool = false,
    widgetStore: WidgetValueStore? = nil,
    widgetCellID: String? = nil,
    widgetsEnabled: Bool = false,
    kernelSessionID: String? = nil,
    sendWidgetValue: @escaping @MainActor @Sendable (String, Double, String) -> Void = {
      _, _, _ in
    }
  ) {
    self.output = output
    self.stale = stale
    self.running = running
    self.widgetStore = widgetStore
    self.widgetCellID = widgetCellID
    self.widgetsEnabled = widgetsEnabled
    self.kernelSessionID = kernelSessionID
    self.sendWidgetValue = sendWidgetValue
  }

  public var body: some View {
    Group {
      if let prepared {
        preparedView(prepared)
      } else {
        ProgressView("Preparing output…")
          .controlSize(.small)
      }
    }
    .frame(
      width: output.displaySize?.width.map { CGFloat($0) },
      height: output.displaySize?.height.map { CGFloat($0) },
      alignment: .topLeading
    )
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    .opacity(stale ? 0.62 : 1)
    .overlay(alignment: .topTrailing) {
      if running {
        Label("Running", systemImage: "progress.indicator")
          .font(.caption)
          .padding(6)
          .background(.background.opacity(0.9), in: Capsule())
          .accessibilityValue("Previous output remains visible while the cell is running")
      } else if stale {
        Label("Stale", systemImage: "clock.arrow.circlepath")
          .font(.caption)
          .padding(6)
          .background(.background.opacity(0.9), in: Capsule())
          .accessibilityValue("Cell output is stale")
      }
    }
    .task(id: preparationID) {
      prepared = nil
      let result = await OutputPreparationService.shared.prepare(output)
      guard !Task.isCancelled else { return }
      prepared = result
    }
  }

  @ViewBuilder
  private func preparedView(_ value: PreparedOutput) -> some View {
    switch value {
    case .text(let text, let masked):
      Text(masked ? String(repeating: "•", count: min(text.count, 64)) : text)
        .font(.body.monospaced())
        .textSelection(.enabled)
        .accessibilityLabel(masked ? "Masked output" : "Text output")
    case .json(let root):
      JSONOutlineView(node: root, initiallyExpanded: true)
        .accessibilityLabel("JSON output")
    case .errors(let errors):
      VStack(alignment: .leading, spacing: 8) {
        ForEach(errors) { error in
          HStack(alignment: .top, spacing: 8) {
            Image(
              systemName: error.kind == "interruption"
                ? "stop.circle" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(error.kind == "interruption" ? Color.secondary : Color.red)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
              Text(error.kind).font(.caption.monospaced()).foregroundStyle(.secondary)
              Text(
                error.kind == "interruption"
                  ? localizedUI("Execution was stopped. You can run this cell again.")
                  : error.message
              ).textSelection(.enabled)
              if let line = error.line { Text("Line \(line)").font(.caption) }
            }
          }
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Execution errors")
    case .traceback(let lines):
      DisclosureGroup("Details") {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(lines) { line in
            if let url = line.fileURL {
              HStack(alignment: .firstTextBaseline) {
                Text(line.text)
                  .font(.body.monospaced())
                  .textSelection(.enabled)
                  .frame(maxWidth: .infinity, alignment: .leading)
                Link(destination: url) {
                  Image(systemName: "arrow.up.forward.square")
                }
                .accessibilityLabel("Open traceback source")
              }
              .help(line.line.map { "Open \(url.path), line \($0)" } ?? "Open \(url.path)")
            } else {
              Text(line.text).font(.body.monospaced()).textSelection(.enabled)
            }
          }
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Python traceback")
    case .image(let decoded):
      Image(decorative: decoded.image, scale: 1, orientation: .up)
        .resizable()
        .scaledToFit()
        .frame(
          width: output.displaySize?.width.map { CGFloat($0) },
          height: output.displaySize?.height.map { CGFloat($0) }
        )
        .frame(
          maxWidth: output.displaySize?.width == nil ? CGFloat(decoded.pixelWidth) : nil,
          maxHeight: output.displaySize?.height == nil ? CGFloat(decoded.pixelHeight) : nil
        )
        .accessibilityLabel("Image output, \(decoded.pixelWidth) by \(decoded.pixelHeight) pixels")
    case .csv(let table):
      CSVTableView(table: table)
        .frame(height: min(360, max(80, CGFloat(table.rows.count + 1) * 24)))
        .accessibilityLabel("CSV table output")
    case .nativeHTML(let text):
      Text(text)
        .font(.body.monospaced())
        .textSelection(.enabled)
        .accessibilityLabel("Native HTML output")
        .accessibilityValue(text)
    case .slider(let descriptor):
      if let widgetStore, let widgetCellID {
        NativeSliderView(
          descriptor: descriptor,
          store: widgetStore,
          cellID: widgetCellID,
          interactionEnabled: widgetsEnabled && !stale && kernelSessionID != nil,
          onSend: { value in
            if let kernelSessionID {
              sendWidgetValue(descriptor.objectID, value, kernelSessionID)
            }
          }
        )
      } else {
        recoveryView(
          title: "Interactive output unavailable",
          detail: "The slider is not attached to a current kernel session.",
          raw: String(describing: output.data)
        )
      }
    case .mimeBundle(let bundle):
      MIMEBundleView(
        output: output,
        bundle: bundle,
        widgetStore: widgetStore,
        widgetCellID: widgetCellID,
        widgetsEnabled: widgetsEnabled,
        kernelSessionID: kernelSessionID,
        sendWidgetValue: sendWidgetValue
      )
      .id(bundle.representations.map(\.mimeType).joined(separator: "|"))
    case .web(let payload):
      CellWebOutputView(payload: payload)
    case .unsupported(let mimeType, let size, let raw):
      recoveryView(
        title: "Unsupported output",
        detail:
          "\(mimeType) · \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))",
        raw: raw
      )
    case .failure(let mimeType, let message, let size, let raw):
      recoveryView(
        title: "Output could not be rendered",
        detail:
          "\(mimeType) · \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))\n\(message)",
        raw: raw
      )
    }
  }

  private func recoveryView(title: String, detail: String, raw: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: "doc.questionmark")
        .font(.headline)
      Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      HStack {
        Button("Copy Raw Data", systemImage: "doc.on.doc") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(raw, forType: .string)
        }
        Button("Save Raw Data…", systemImage: "square.and.arrow.down") {
          save(raw)
        }
      }
    }
  }

  private var preparationID: String {
    "\(output.mimeType)|\(output.timestamp ?? 0)|\(output.data.hashValue)"
  }

  private func save(_ raw: String) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "output.txt"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    try? Data(raw.utf8).write(to: url, options: .atomic)
  }
}

private struct MIMEBundleView: View {
  let output: MarimoOutput
  let bundle: ResolvedMIMEBundle
  let widgetStore: WidgetValueStore?
  let widgetCellID: String?
  let widgetsEnabled: Bool
  let kernelSessionID: String?
  let sendWidgetValue: @MainActor @Sendable (String, Double, String) -> Void
  @State private var selectedMIME: String

  init(
    output: MarimoOutput,
    bundle: ResolvedMIMEBundle,
    widgetStore: WidgetValueStore?,
    widgetCellID: String?,
    widgetsEnabled: Bool,
    kernelSessionID: String?,
    sendWidgetValue: @escaping @MainActor @Sendable (String, Double, String) -> Void
  ) {
    self.output = output
    self.bundle = bundle
    self.widgetStore = widgetStore
    self.widgetCellID = widgetCellID
    self.widgetsEnabled = widgetsEnabled
    self.kernelSessionID = kernelSessionID
    self.sendWidgetValue = sendWidgetValue
    _selectedMIME = State(initialValue: bundle.representations.first?.mimeType ?? "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if bundle.representations.count > 1 {
        Picker("Output Format", selection: $selectedMIME) {
          ForEach(bundle.representations) { representation in
            Text(representation.mimeType).tag(representation.mimeType)
          }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("Output format")
      }
      if let representation = selectedRepresentation {
        OutputView(
          output: representation.output(inheriting: output),
          widgetStore: widgetStore,
          widgetCellID: widgetCellID,
          widgetsEnabled: widgetsEnabled,
          kernelSessionID: kernelSessionID,
          sendWidgetValue: sendWidgetValue
        )
      }
    }
  }

  private var selectedRepresentation: MIMEBundleRepresentation? {
    bundle.representations.first { $0.mimeType == selectedMIME }
      ?? bundle.representations.first
  }
}

private struct JSONOutlineView: View {
  let node: JSONOutlineNode
  let initiallyExpanded: Bool
  @State private var expanded: Bool

  init(node: JSONOutlineNode, initiallyExpanded: Bool = false) {
    self.node = node
    self.initiallyExpanded = initiallyExpanded
    _expanded = State(initialValue: initiallyExpanded)
  }

  var body: some View {
    if node.children.isEmpty {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(node.label).font(.body.monospaced()).foregroundStyle(.secondary)
        Text(node.value ?? "").font(.body.monospaced()).textSelection(.enabled)
      }
    } else {
      DisclosureGroup(isExpanded: $expanded) {
        LazyVStack(alignment: .leading, spacing: 3) {
          ForEach(node.children) { child in
            JSONOutlineView(node: child).padding(.leading, 12)
          }
        }
      } label: {
        Text("\(node.label) \(node.value ?? "")").font(.body.monospaced())
      }
    }
  }
}
