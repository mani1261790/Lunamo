import Foundation
import MarimoDomain
import MarimoOutput
import Testing

@testable import MarimoWidgets

@Suite("Native marimo slider")
struct MarimoComponentDecoderTests {
  @Test("HTML entities and JSON attributes decode into the strict slider schema")
  func entityAndJSONDecoding() throws {
    let descriptor = try #require(
      MarimoComponentDecoder.slider(
        from: sliderHTML(
          label: "&quot;Value &amp; More&quot;",
          steps: "[2,4,8]",
          initialValue: "1",
          start: "0",
          stop: "2",
          debounce: "true",
          orientation: "&quot;vertical&quot;",
          showValue: "true",
          fullWidth: "true",
          includeInput: "true"
        )
      )
    )
    #expect(descriptor.objectID == "shared-slider")
    #expect(descriptor.randomID == "random-one")
    #expect(descriptor.labelHTML == "Value & More")
    #expect(descriptor.steps == [2, 4, 8])
    #expect(descriptor.debounce)
    #expect(descriptor.orientation == .vertical)
    #expect(descriptor.showValue)
    #expect(descriptor.fullWidth)
    #expect(descriptor.includeInput)
    #expect(descriptor.displayValue(for: descriptor.initialValue) == 4)
    #expect(descriptor.position(forDisplayValue: 8) == 2)
  }

  @Test("Only one exact marimo slider root enters the native path")
  func strictRootBoundary() {
    let valid = sliderHTML()
    #expect(MarimoComponentDecoder.slider(from: valid) != nil)
    #expect(MarimoComponentDecoder.slider(from: valid + "<p>sibling</p>") == nil)
    #expect(
      MarimoComponentDecoder.slider(
        from: valid.replacingOccurrences(of: "marimo-slider", with: "marimo-checkbox")
      ) == nil
    )
    #expect(
      MarimoComponentDecoder.slider(
        from: valid.replacingOccurrences(
          of: "</marimo-ui-element>", with: "text</marimo-ui-element>")
      ) == nil
    )
  }

  @Test("Valid sliders prepare natively while invalid schemas use the isolated fallback")
  func outputPreparationBoundary() {
    let valid = OutputPreparationService.prepareSynchronously(
      MarimoOutput(channel: .output, mimeType: "text/html", data: .string(sliderHTML()))
    )
    guard case .slider(let descriptor) = valid else {
      Issue.record("Valid slider did not enter the native renderer")
      return
    }
    #expect(descriptor.initialValue == 2)

    let invalid = OutputPreparationService.prepareSynchronously(
      MarimoOutput(
        channel: .output,
        mimeType: "text/html",
        data: .string(sliderHTML(step: "0"))
      )
    )
    guard case .web(let payload) = invalid else {
      Issue.record("Invalid slider did not fall back safely")
      return
    }
    #expect(payload.kind == .html)
  }

  @Test("Invalid numeric, orientation, boolean, and range schemas fall back safely")
  func invalidSchema() {
    let invalid = [
      sliderHTML(initialValue: "&quot;NaN&quot;"),
      sliderHTML(start: "10", stop: "0"),
      sliderHTML(step: "0"),
      sliderHTML(orientation: "&quot;diagonal&quot;"),
      sliderHTML(debounce: "1"),
      sliderHTML(steps: "[1,true,3]", initialValue: "1", start: "0", stop: "2"),
      sliderHTML(steps: "[1,2]", initialValue: "4", start: "0", stop: "1"),
    ]
    for source in invalid {
      #expect(MarimoComponentDecoder.slider(from: source) == nil)
    }
  }

  @Test("A shared object ID synchronizes views and a new random ID resets the value")
  @MainActor
  func sharedStoreAndRandomReset() throws {
    let first = try #require(MarimoComponentDecoder.slider(from: sliderHTML()))
    let store = WidgetValueStore()
    store.register(first, cellID: "cell-a")
    store.register(first, cellID: "cell-b")
    store.setValue(7, for: first)
    #expect(store.value(for: first) == 7)

    let replacement = try #require(
      MarimoComponentDecoder.slider(
        from: sliderHTML(randomID: "random-two", initialValue: "3")
      )
    )
    store.register(replacement, cellID: "cell-a")
    let reset = try #require(store.snapshot(for: first.objectID))
    #expect(reset.randomID == "random-two")
    #expect(reset.value == 3)
    #expect(reset.generation == 1)

    store.remove(cellID: "cell-a")
    #expect(store.snapshot(for: first.objectID) != nil)
    store.remove(cellID: "cell-b")
    #expect(store.snapshot(for: first.objectID) == nil)
  }

  @Test("Continuous updates are capped while debounce waits for commit")
  @MainActor
  func updateRateAndDebounce() async {
    let dispatcher = SliderUpdateDispatcher()
    let continuous = DispatchRecorder()
    for value in 0..<100 {
      dispatcher.changed(Double(value), debounce: false) { continuous.append($0) }
    }
    try? await Task.sleep(for: .milliseconds(80))
    #expect(continuous.values.count <= 4)
    dispatcher.finish(99) { continuous.append($0) }
    #expect(continuous.values.last == 99)

    let debounce = SliderUpdateDispatcher()
    let committed = DispatchRecorder()
    for value in 0..<20 {
      debounce.changed(Double(value), debounce: true) { committed.append($0) }
    }
    try? await Task.sleep(for: .milliseconds(40))
    #expect(committed.values.isEmpty)
    debounce.finish(19) { committed.append($0) }
    #expect(committed.values == [19])
  }

  private func sliderHTML(
    objectID: String = "shared-slider",
    randomID: String = "random-one",
    label: String = "null",
    steps: String = "[]",
    initialValue: String = "2",
    start: String = "0",
    stop: String = "10",
    step: String? = nil,
    debounce: String = "false",
    orientation: String = "&quot;horizontal&quot;",
    showValue: String = "false",
    fullWidth: String = "false",
    includeInput: String = "false",
    disabled: String = "false"
  ) -> String {
    let stepAttribute = step.map { " data-step='\($0)'" } ?? ""
    return """
      <marimo-ui-element object-id='\(objectID)' random-id='\(randomID)'>
        <marimo-slider data-initial-value='\(initialValue)' data-label='\(label)'
          data-start='\(start)' data-stop='\(stop)'\(stepAttribute) data-steps='\(steps)'
          data-debounce='\(debounce)' data-disabled='\(disabled)'
          data-orientation='\(orientation)' data-show-value='\(showValue)'
          data-include-input='\(includeInput)' data-full-width='\(fullWidth)'>
        </marimo-slider>
      </marimo-ui-element>
      """
  }
}

@MainActor
private final class DispatchRecorder {
  var values: [Double] = []
  func append(_ value: Double) { values.append(value) }
}
