import Flutter
import Foundation

struct IncomingAudioReceipt: Codable, Equatable {
  let id: String
  let copiedCount: Int
  let failedCount: Int
  let ignoredCount: Int

  var dictionary: [String: Any] {
    [
      "id": id,
      "copiedCount": copiedCount,
      "failedCount": failedCount,
      "ignoredCount": ignoredCount,
    ]
  }
}

final class IncomingAudioImportStore {
  static let shared = IncomingAudioImportStore()

  private static let channelName = "com.chx.clutter/incoming_audio"
  private static let supportedExtensions: Set<String> = [
    "mp3", "flac", "m4a", "mp4", "ogg", "opus", "wav",
  ]

  private let fileManager: FileManager
  private let defaults: UserDefaults
  private let documentsDirectory: URL
  private let receiptsKey: String
  private let workQueue: DispatchQueue
  private var channel: FlutterMethodChannel?

  init(
    fileManager: FileManager = .default,
    defaults: UserDefaults = .standard,
    documentsDirectory: URL? = nil,
    receiptsKey: String = "incoming_audio_receipts",
    workQueue: DispatchQueue = DispatchQueue(
      label: "com.chx.clutter.incoming-audio",
      qos: .utility
    )
  ) {
    self.fileManager = fileManager
    self.defaults = defaults
    self.documentsDirectory =
      documentsDirectory
      ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    self.receiptsKey = receiptsKey
    self.workQueue = workQueue
  }

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "unavailable",
            message: "incoming audio service is unavailable",
            details: nil
          )
        )
        return
      }
      switch call.method {
      case "listPendingImports":
        self.workQueue.async {
          let pending = self.loadReceipts().map(\.dictionary)
          DispatchQueue.main.async { result(pending) }
        }
      case "acknowledgeImports":
        guard let ids = call.arguments as? [String] else {
          result(
            FlutterError(
              code: "invalid_arguments",
              message: "expected a list of receipt ids",
              details: nil
            )
          )
          return
        }
        self.workQueue.async {
          self.acknowledge(ids: Set(ids))
          DispatchQueue.main.async { result(nil) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  func accept(urls: [URL]) {
    guard !urls.isEmpty else { return }
    workQueue.async {
      var receipts = self.loadReceipts()
      for url in urls {
        receipts.append(self.importURL(url))
      }
      self.saveReceipts(receipts)
      DispatchQueue.main.async {
        self.channel?.invokeMethod("importsAvailable", arguments: nil)
      }
    }
  }

  func importURL(_ url: URL) -> IncomingAudioReceipt {
    let accessed = url.startAccessingSecurityScopedResource()
    defer {
      if accessed { url.stopAccessingSecurityScopedResource() }
    }

    var copiedCount = 0
    var failedCount = 0
    var ignoredCount = 0
    var coordinationError: NSError?
    let coordinator = NSFileCoordinator()
    coordinator.coordinate(
      readingItemAt: url,
      options: .withoutChanges,
      error: &coordinationError
    ) { coordinatedURL in
      let result = self.copyCoordinatedURL(coordinatedURL)
      copiedCount = result.copied
      failedCount = result.failed
      ignoredCount = result.ignored
    }
    if coordinationError != nil {
      failedCount += 1
    }

    return IncomingAudioReceipt(
      id: UUID().uuidString,
      copiedCount: copiedCount,
      failedCount: failedCount,
      ignoredCount: ignoredCount
    )
  }

  func pendingReceipts() -> [IncomingAudioReceipt] {
    loadReceipts()
  }

  func acknowledge(ids: Set<String>) {
    guard !ids.isEmpty else { return }
    saveReceipts(loadReceipts().filter { !ids.contains($0.id) })
  }

  private func copyCoordinatedURL(
    _ source: URL
  ) -> (copied: Int, failed: Int, ignored: Int) {
    do {
      let values = try source.resourceValues(forKeys: [
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
      ])
      if values.isSymbolicLink == true {
        return (0, 0, 1)
      }
      if values.isDirectory == true {
        return copyFolder(source)
      }
      if values.isRegularFile == true {
        return copyFile(source)
      }
      return (0, 0, 1)
    } catch {
      return (0, 1, 0)
    }
  }

  private func copyFile(
    _ source: URL
  ) -> (copied: Int, failed: Int, ignored: Int) {
    guard isSupportedAudio(source) else { return (0, 0, 1) }
    let stagingRoot = makeStagingRoot()
    let staged = stagingRoot.appendingPathComponent(source.lastPathComponent)
    do {
      try fileManager.createDirectory(
        at: stagingRoot,
        withIntermediateDirectories: true
      )
      try fileManager.copyItem(at: source, to: staged)
      let destination = uniqueDestination(
        named: source.lastPathComponent,
        isDirectory: false
      )
      try fileManager.createDirectory(
        at: musicDirectory,
        withIntermediateDirectories: true
      )
      try fileManager.moveItem(at: staged, to: destination)
      try? fileManager.removeItem(at: stagingRoot)
      return (1, 0, 0)
    } catch {
      try? fileManager.removeItem(at: stagingRoot)
      return (0, 1, 0)
    }
  }

  private func copyFolder(
    _ source: URL
  ) -> (copied: Int, failed: Int, ignored: Int) {
    let stagingRoot = makeStagingRoot()
    let folderName = source.lastPathComponent.isEmpty
      ? "Imported Audio"
      : source.lastPathComponent
    let stagedFolder = stagingRoot.appendingPathComponent(
      folderName,
      isDirectory: true
    )
    var copied = 0
    var failed = 0
    var ignored = 0

    do {
      try fileManager.createDirectory(
        at: stagedFolder,
        withIntermediateDirectories: true
      )
      let keys: [URLResourceKey] = [
        .isRegularFileKey,
        .isSymbolicLinkKey,
      ]
      guard
        let enumerator = fileManager.enumerator(
          at: source,
          includingPropertiesForKeys: keys,
          options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
      else {
        try? fileManager.removeItem(at: stagingRoot)
        return (0, 1, 0)
      }

      let sourceComponents = source.standardizedFileURL.pathComponents.count
      for case let item as URL in enumerator {
        let values = try? item.resourceValues(forKeys: Set(keys))
        if values?.isSymbolicLink == true {
          ignored += 1
          continue
        }
        guard values?.isRegularFile == true else { continue }
        guard isSupportedAudio(item) else {
          ignored += 1
          continue
        }
        let relativeComponents = item.standardizedFileURL.pathComponents
          .dropFirst(sourceComponents)
        var destination = stagedFolder
        for component in relativeComponents {
          destination.appendPathComponent(component)
        }
        do {
          try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
          )
          try fileManager.copyItem(at: item, to: destination)
          copied += 1
        } catch {
          failed += 1
        }
      }

      guard copied > 0 else {
        try? fileManager.removeItem(at: stagingRoot)
        return (0, failed, ignored)
      }
      try fileManager.createDirectory(
        at: musicDirectory,
        withIntermediateDirectories: true
      )
      let destination = uniqueDestination(
        named: folderName,
        isDirectory: true
      )
      try fileManager.moveItem(at: stagedFolder, to: destination)
      try? fileManager.removeItem(at: stagingRoot)
      return (copied, failed, ignored)
    } catch {
      try? fileManager.removeItem(at: stagingRoot)
      return (0, failed + max(copied, 1), ignored)
    }
  }

  private var musicDirectory: URL {
    documentsDirectory.appendingPathComponent("Music", isDirectory: true)
  }

  private func makeStagingRoot() -> URL {
    documentsDirectory
      .appendingPathComponent("clutter", isDirectory: true)
      .appendingPathComponent("incoming", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
  }

  private func uniqueDestination(named name: String, isDirectory: Bool) -> URL {
    let proposed = musicDirectory.appendingPathComponent(
      name,
      isDirectory: isDirectory
    )
    guard fileManager.fileExists(atPath: proposed.path) else { return proposed }

    let source = URL(fileURLWithPath: name)
    let fileExtension = isDirectory ? "" : source.pathExtension
    let stem = isDirectory
      ? name
      : source.deletingPathExtension().lastPathComponent
    var index = 2
    while true {
      let suffix = "\(stem) (\(index))"
      let candidateName = fileExtension.isEmpty
        ? suffix
        : "\(suffix).\(fileExtension)"
      let candidate = musicDirectory.appendingPathComponent(
        candidateName,
        isDirectory: isDirectory
      )
      if !fileManager.fileExists(atPath: candidate.path) {
        return candidate
      }
      index += 1
    }
  }

  private func isSupportedAudio(_ url: URL) -> Bool {
    Self.supportedExtensions.contains(url.pathExtension.lowercased())
  }

  private func loadReceipts() -> [IncomingAudioReceipt] {
    guard let data = defaults.data(forKey: receiptsKey) else { return [] }
    return (try? JSONDecoder().decode([IncomingAudioReceipt].self, from: data))
      ?? []
  }

  private func saveReceipts(_ receipts: [IncomingAudioReceipt]) {
    guard !receipts.isEmpty else {
      defaults.removeObject(forKey: receiptsKey)
      return
    }
    defaults.set(try? JSONEncoder().encode(receipts), forKey: receiptsKey)
  }
}
