import Darwin
import Foundation

public enum NotebookPresentedFileEvent: Sendable, Equatable {
  case changed(URL)
  case moved(from: URL, to: URL)
  case deleted(URL)
}

public final class NotebookFilePresenter: NSObject, NSFilePresenter, @unchecked Sendable {
  private let lock = NSLock()
  private var itemURL: URL?
  private var isRegistered = true
  private let eventHandler: @Sendable (NotebookPresentedFileEvent) -> Void
  private var fileSystemSource: DispatchSourceFileSystemObject?

  public let presentedItemOperationQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "dev.marimonative.file-presenter"
    queue.maxConcurrentOperationCount = 1
    queue.qualityOfService = .utility
    return queue
  }()

  public var presentedItemURL: URL? {
    lock.withLock { itemURL }
  }

  public init(url: URL, eventHandler: @escaping @Sendable (NotebookPresentedFileEvent) -> Void) {
    itemURL = url.standardizedFileURL
    self.eventHandler = eventHandler
    super.init()
    NSFileCoordinator.addFilePresenter(self)
    startFileSystemMonitoring(at: url)
  }

  deinit {
    unregister()
  }

  public func stop() {
    unregister()
    fileSystemSource?.cancel()
    fileSystemSource = nil
    presentedItemOperationQueue.cancelAllOperations()
  }

  private func startFileSystemMonitoring(at url: URL) {
    let descriptor = open(url.path, O_EVTONLY)
    guard descriptor >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .delete, .attrib, .extend, .link, .revoke],
      queue: DispatchQueue.global(qos: .utility)
    )
    source.setEventHandler { [weak self, weak source] in
      guard let self, let source, let url = self.presentedItemURL else { return }
      let events = source.data
      if events.contains(.delete) || events.contains(.revoke) {
        self.eventHandler(.deleted(url))
      } else {
        self.eventHandler(.changed(url))
      }
    }
    source.setCancelHandler { close(descriptor) }
    fileSystemSource = source
    source.resume()
  }

  private func unregister() {
    let shouldRemove = lock.withLock {
      guard isRegistered else { return false }
      isRegistered = false
      return true
    }
    if shouldRemove { NSFileCoordinator.removeFilePresenter(self) }
  }

  public func presentedItemDidChange() {
    guard let url = presentedItemURL else { return }
    eventHandler(.changed(url))
  }

  public func presentedItemDidMove(to newURL: URL) {
    let newURL = newURL.standardizedFileURL
    guard
      let oldURL = lock.withLock({ () -> URL? in
        let old = itemURL
        itemURL = newURL
        return old
      })
    else { return }
    eventHandler(.moved(from: oldURL, to: newURL))
  }

  public func accommodatePresentedItemDeletion(
    completionHandler: @escaping @Sendable (Error?) -> Void
  ) {
    if let url = presentedItemURL { eventHandler(.deleted(url)) }
    completionHandler(nil)
  }
}
