import MarimoOutput
import SwiftUI

public struct CellWebOutputView: View {
  private static let collapsedHeight: CGFloat = 1_600

  private let payload: WebOutputPayload
  @State private var contentHeight: CGFloat
  @State private var expanded = false
  @State private var failure: String?

  public init(payload: WebOutputPayload) {
    self.payload = payload
    _contentHeight = State(initialValue: CGFloat(payload.displaySize?.height ?? 120))
  }

  public var body: some View {
    Group {
      if let failure {
        ContentUnavailableView(
          "Web output stopped",
          systemImage: "exclamationmark.websearch",
          description: Text(failure)
        )
        .accessibilityLabel("Web output error")
      } else {
        VStack(alignment: .leading, spacing: 8) {
          IsolatedWebOutputView(
            payload: payload,
            internalScrollingEnabled: expanded,
            contentHeight: $contentHeight,
            failure: $failure
          )
          .frame(
            width: payload.displaySize?.width.map { CGFloat($0) },
            height: min(contentHeight, Self.collapsedHeight)
          )
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityLabel("Isolated web output")

          if contentHeight > Self.collapsedHeight, !expanded {
            Button("Expand Web Output", systemImage: "arrow.up.left.and.arrow.down.right") {
              expanded = true
            }
            .accessibilityHint("Allows scrolling inside this output")
          }
        }
      }
    }
  }
}
