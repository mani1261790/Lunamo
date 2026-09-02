import AppKit
import Foundation
import MarimoDomain

@MainActor
enum ReleasePerformanceProbe {
  static var fixtureDocument: NotebookDocumentState? {
    let arguments = CommandLine.arguments
    guard arguments.contains("--performance-scroll-fixture") else { return nil }
    let output = imageOutput()
    let cells = (0..<100).map { index in
      NotebookCellState(
        code: (0..<10).map { line in "value_\(index)_\(line) = \(line)" }.joined(separator: "\n"),
        runtime: CellRuntimeState(output: output)
      )
    }
    let owned = OwnedNotebookDocumentV1(
      cells: cells.map { cell in OwnedNotebookCell(code: cell.code, name: cell.name) },
      header: ""
    )
    return NotebookDocumentState(owned: owned, cells: cells)
  }

  static func recordWindowPresented() {
    record(flag: "--performance-window-marker", value: "window-presented")
  }

  static func recordLoadedCellCount(_ count: Int) {
    guard count >= 100 else { return }
    record(flag: "--performance-cells-marker", value: "cells=\(count)")
  }

  static func recordBackendStatus(_ status: BackendStatus) {
    guard status == .ready else { return }
    record(flag: "--performance-backend-marker", value: "backend-ready")
  }

  static func runScrollProbe() async {
    guard CommandLine.arguments.contains("--performance-scroll-fixture") else { return }
    var located: (NSView, NSScrollView)?
    for _ in 0..<50 {
      try? await Task.sleep(for: .milliseconds(100))
      guard
        let contentView = NSApplication.shared.windows.compactMap(\.contentView).first,
        let scrollView = scrollViews(in: contentView).max(by: {
          ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0)
        })
      else { continue }
      located = (contentView, scrollView)
      break
    }
    guard let (contentView, scrollView) = located, let documentView = scrollView.documentView else {
      record(flag: "--performance-scroll-marker", value: "error=no-scroll-view")
      return
    }

    let maximumY = max(0, documentView.frame.height - scrollView.contentView.bounds.height)
    var maximumDelay = 0.0
    var previous = ContinuousClock.now
    for step in 0..<240 {
      try? await Task.sleep(for: .milliseconds(16))
      let now = ContinuousClock.now
      maximumDelay = max(maximumDelay, milliseconds(previous.duration(to: now)) - 16)
      previous = now
      let phase = step < 120 ? Double(step) / 119 : Double(239 - step) / 119
      let startedLayout = ContinuousClock.now
      scrollView.contentView.scroll(to: NSPoint(x: 0, y: maximumY * phase))
      scrollView.reflectScrolledClipView(scrollView.contentView)
      contentView.layoutSubtreeIfNeeded()
      maximumDelay = max(
        maximumDelay,
        milliseconds(startedLayout.duration(to: ContinuousClock.now))
      )
    }
    record(
      flag: "--performance-scroll-marker",
      value: "maxMainThreadDelayMilliseconds=\(maximumDelay) decodedImageMiB=50"
    )
  }

  private static func record(flag: String, value: String) {
    guard let marker = markerURL(after: flag) else { return }
    do {
      try Data(value.utf8).write(to: marker, options: .withoutOverwriting)
    } catch {
      MarimoLog.app.error("Performance marker write failed")
    }
  }

  private static func markerURL(after flag: String) -> URL? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
      return nil
    }
    let marker = URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL
    let temporaryRoot = FileManager.default.temporaryDirectory.standardizedFileURL.path
    guard marker.path.hasPrefix(temporaryRoot + "/") else {
      MarimoLog.app.error("Performance marker must be inside the temporary directory")
      return nil
    }
    return marker
  }

  private static func imageOutput() -> MarimoOutput? {
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 512,
        pixelsHigh: 256,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 2_048,
        bitsPerPixel: 32
      ),
      let png = bitmap.representation(using: .png, properties: [:])
    else { return nil }
    return MarimoOutput(
      channel: .output,
      mimeType: "image/png",
      data: .string(png.base64EncodedString()),
      displaySize: OutputDisplaySize(width: 512, height: 256)
    )
  }

  private static func scrollViews(in view: NSView) -> [NSScrollView] {
    var result: [NSScrollView] = []
    if let scrollView = view as? NSScrollView { result.append(scrollView) }
    for child in view.subviews {
      result.append(contentsOf: scrollViews(in: child))
    }
    return result
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }
}
