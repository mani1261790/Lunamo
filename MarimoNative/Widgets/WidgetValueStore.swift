import Combine
import Foundation

public struct WidgetValueSnapshot: Sendable, Equatable {
  public let objectID: String
  public let randomID: String
  public let value: Double
  public let generation: UInt64
}

@MainActor
public final class WidgetValueStore: ObservableObject {
  private struct Entry: Equatable {
    var descriptor: MarimoSliderDescriptor
    var value: Double
    var generation: UInt64
    var cellIDs: Set<String>
  }

  @Published private var entries: [String: Entry] = [:]

  public init() {}

  public var objectIDs: [String] { entries.keys.sorted() }

  public func synchronize(cellID: String, descriptors: [MarimoSliderDescriptor]) {
    let incoming = Set(descriptors.map(\.objectID))
    for objectID in Array(entries.keys)
    where entries[objectID]?.cellIDs.contains(cellID) == true
      && !incoming.contains(objectID)
    {
      entries[objectID]?.cellIDs.remove(cellID)
      if entries[objectID]?.cellIDs.isEmpty == true { entries.removeValue(forKey: objectID) }
    }
    for descriptor in descriptors { register(descriptor, cellID: cellID) }
  }

  public func register(_ descriptor: MarimoSliderDescriptor, cellID: String) {
    if var entry = entries[descriptor.objectID] {
      if entry.descriptor.randomID != descriptor.randomID {
        entry.descriptor = descriptor
        entry.value = descriptor.initialValue
        entry.generation &+= 1
      } else {
        entry.descriptor = descriptor
      }
      entry.cellIDs.insert(cellID)
      entries[descriptor.objectID] = entry
    } else {
      entries[descriptor.objectID] = Entry(
        descriptor: descriptor,
        value: descriptor.initialValue,
        generation: 0,
        cellIDs: [cellID]
      )
    }
  }

  public func snapshot(for objectID: String) -> WidgetValueSnapshot? {
    guard let entry = entries[objectID] else { return nil }
    return WidgetValueSnapshot(
      objectID: objectID,
      randomID: entry.descriptor.randomID,
      value: entry.value,
      generation: entry.generation
    )
  }

  public func value(for descriptor: MarimoSliderDescriptor) -> Double {
    entries[descriptor.objectID]?.value ?? descriptor.initialValue
  }

  public func setValue(_ value: Double, for descriptor: MarimoSliderDescriptor) {
    let normalized = descriptor.normalizedPosition(value)
    guard var entry = entries[descriptor.objectID], entry.descriptor.randomID == descriptor.randomID
    else { return }
    guard entry.value != normalized else { return }
    entry.value = normalized
    entries[descriptor.objectID] = entry
  }

  public func receiveKernelValue(_ value: Double, objectID: String) {
    guard var entry = entries[objectID] else { return }
    let normalized = entry.descriptor.normalizedPosition(value)
    guard entry.value != normalized else { return }
    entry.value = normalized
    entries[objectID] = entry
  }

  public func remove(cellID: String) {
    for objectID in Array(entries.keys) where entries[objectID]?.cellIDs.contains(cellID) == true {
      entries[objectID]?.cellIDs.remove(cellID)
      if entries[objectID]?.cellIDs.isEmpty == true { entries.removeValue(forKey: objectID) }
    }
  }

  public func clear() {
    entries.removeAll()
  }
}
