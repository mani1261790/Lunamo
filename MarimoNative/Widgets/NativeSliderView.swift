import AppKit
import SwiftUI

@MainActor
final class SliderUpdateDispatcher: ObservableObject {
  static let intervalNanoseconds: UInt64 = 33_333_334

  private var lastSentNanoseconds: UInt64?
  private var pendingValue: Double?
  private var pendingTask: Task<Void, Never>?

  func changed(
    _ value: Double,
    debounce: Bool,
    send: @escaping @MainActor @Sendable (Double) -> Void
  ) {
    pendingValue = value
    guard !debounce else { return }
    let now = DispatchTime.now().uptimeNanoseconds
    if let lastSentNanoseconds {
      let elapsed = now &- lastSentNanoseconds
      guard elapsed < Self.intervalNanoseconds else {
        sendImmediately(value, at: now, send: send)
        return
      }
      guard pendingTask == nil else { return }
      let delay = Self.intervalNanoseconds - elapsed
      pendingTask = Task { @MainActor [weak self] in
        try? await Task.sleep(nanoseconds: delay)
        guard !Task.isCancelled, let self, let latest = self.pendingValue else { return }
        self.pendingTask = nil
        self.sendImmediately(latest, at: DispatchTime.now().uptimeNanoseconds, send: send)
      }
    } else {
      sendImmediately(value, at: now, send: send)
    }
  }

  func finish(_ value: Double, send: @escaping @MainActor @Sendable (Double) -> Void) {
    pendingTask?.cancel()
    pendingTask = nil
    pendingValue = nil
    lastSentNanoseconds = DispatchTime.now().uptimeNanoseconds
    send(value)
  }

  func cancel() {
    pendingTask?.cancel()
    pendingTask = nil
    pendingValue = nil
  }

  private func sendImmediately(
    _ value: Double,
    at now: UInt64,
    send: @escaping @MainActor @Sendable (Double) -> Void
  ) {
    pendingTask?.cancel()
    pendingTask = nil
    pendingValue = nil
    lastSentNanoseconds = now
    send(value)
  }
}

public struct NativeSliderView: View {
  public let descriptor: MarimoSliderDescriptor
  @ObservedObject private var store: WidgetValueStore
  private let cellID: String
  private let interactionEnabled: Bool
  private let onSend: @MainActor @Sendable (Double) -> Void

  @StateObject private var dispatcher = SliderUpdateDispatcher()
  @State private var inputValue: Double

  public init(
    descriptor: MarimoSliderDescriptor,
    store: WidgetValueStore,
    cellID: String,
    interactionEnabled: Bool,
    onSend: @escaping @MainActor @Sendable (Double) -> Void
  ) {
    self.descriptor = descriptor
    self.store = store
    self.cellID = cellID
    self.interactionEnabled = interactionEnabled
    self.onSend = onSend
    _inputValue = State(initialValue: descriptor.displayValue(for: descriptor.initialValue))
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let label = MarimoComponentDecoder.plainText(fromHTML: descriptor.labelHTML) {
        Text(label)
          .font(.callout)
          .textSelection(.enabled)
      }
      HStack(alignment: .center, spacing: 10) {
        PlatformSlider(
          value: positionBinding,
          range: descriptor.positionRange,
          step: descriptor.steps?.isEmpty == false ? 1 : descriptor.step,
          orientation: descriptor.orientation,
          onContinuousChange: { value in
            dispatcher.changed(value, debounce: descriptor.debounce, send: onSend)
          },
          onCommit: { value in
            dispatcher.finish(value, send: onSend)
          }
        )
        .frame(
          width: descriptor.orientation == .vertical ? 28 : nil,
          height: descriptor.orientation == .vertical ? 180 : 28
        )
        .frame(maxWidth: descriptor.fullWidth ? .infinity : 320)

        if descriptor.showValue {
          Text(formatted(displayValue))
            .font(.body.monospacedDigit())
            .accessibilityLabel("Slider value")
            .accessibilityValue(formatted(displayValue))
        }

        if descriptor.includeInput {
          TextField("Slider value", value: $inputValue, format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 92)
            .onSubmit { commitInput() }
            .accessibilityValue(formatted(inputValue))
        }
      }
    }
    .disabled(descriptor.disabled || !interactionEnabled)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Native marimo slider")
    .accessibilityValue(formatted(displayValue))
    .id("\(descriptor.objectID)|\(descriptor.randomID)")
    .onAppear {
      store.register(descriptor, cellID: cellID)
      inputValue = displayValue
    }
    .onChange(of: displayValue) { _, value in inputValue = value }
    .onDisappear { dispatcher.cancel() }
  }

  private var position: Double { store.value(for: descriptor) }
  private var displayValue: Double { descriptor.displayValue(for: position) }

  private var positionBinding: Binding<Double> {
    Binding(
      get: { position },
      set: { value in
        let normalized = descriptor.normalizedPosition(value)
        store.setValue(normalized, for: descriptor)
        inputValue = descriptor.displayValue(for: normalized)
      }
    )
  }

  private func commitInput() {
    let normalized = descriptor.position(forDisplayValue: inputValue)
    store.setValue(normalized, for: descriptor)
    inputValue = descriptor.displayValue(for: normalized)
    dispatcher.finish(normalized, send: onSend)
  }

  private func formatted(_ value: Double) -> String {
    if value.rounded() == value,
      value >= Double(Int64.min),
      value < Double(Int64.max)
    {
      return String(Int64(value))
    }
    return String(format: "%.6g", value)
  }
}

private struct PlatformSlider: NSViewRepresentable {
  @Binding var value: Double
  let range: ClosedRange<Double>
  let step: Double?
  let orientation: SliderOrientation
  let onContinuousChange: @MainActor @Sendable (Double) -> Void
  let onCommit: @MainActor @Sendable (Double) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  func makeNSView(context: Context) -> CommitAwareSlider {
    let slider = CommitAwareSlider(
      value: value,
      minValue: range.lowerBound,
      maxValue: range.upperBound,
      target: context.coordinator,
      action: #selector(Coordinator.changed(_:))
    )
    slider.isContinuous = true
    slider.onTrackingEnded = { [weak coordinator = context.coordinator] slider in
      coordinator?.finished(slider)
    }
    return slider
  }

  func updateNSView(_ slider: CommitAwareSlider, context: Context) {
    context.coordinator.parent = self
    slider.minValue = range.lowerBound
    slider.maxValue = range.upperBound
    slider.isVertical = orientation == .vertical
    slider.isEnabled = context.environment.isEnabled
    if !slider.isTrackingMouse { slider.doubleValue = value }
  }

  @MainActor
  final class Coordinator: NSObject {
    var parent: PlatformSlider

    init(parent: PlatformSlider) { self.parent = parent }

    @objc func changed(_ sender: CommitAwareSlider) {
      let value = normalized(sender.doubleValue)
      sender.doubleValue = value
      parent.value = value
      if sender.isTrackingMouse {
        parent.onContinuousChange(value)
      } else {
        parent.onCommit(value)
      }
    }

    func finished(_ sender: CommitAwareSlider) {
      let value = normalized(sender.doubleValue)
      sender.doubleValue = value
      parent.value = value
      parent.onCommit(value)
    }

    private func normalized(_ raw: Double) -> Double {
      let clamped = min(max(raw, parent.range.lowerBound), parent.range.upperBound)
      guard let step = parent.step else { return clamped }
      let offset = ((clamped - parent.range.lowerBound) / step).rounded() * step
      let stepped = parent.range.lowerBound + offset
      guard stepped.isFinite else { return clamped }
      return min(max(stepped, parent.range.lowerBound), parent.range.upperBound)
    }
  }
}

@MainActor
private final class CommitAwareSlider: NSSlider {
  var onTrackingEnded: ((CommitAwareSlider) -> Void)?
  private(set) var isTrackingMouse = false

  override func mouseDown(with event: NSEvent) {
    isTrackingMouse = true
    super.mouseDown(with: event)
    isTrackingMouse = false
    onTrackingEnded?(self)
  }
}
