import AppKit
import SwiftUI

/// Native material samples the desktop behind the window.
struct NotebookWindowMaterial: NSViewRepresentable {
  var material: NSVisualEffectView.Material = .sidebar

  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = material
    view.blendingMode = .behindWindow
    view.state = .followsWindowActiveState
    return view
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) {
    view.material = material
  }
}
