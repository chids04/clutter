import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
  private var root: URL!
  private var defaults: UserDefaults!
  private var defaultsSuiteName: String!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    defaultsSuiteName = "IncomingAudioImportTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: defaultsSuiteName)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
    defaults.removePersistentDomain(forName: defaultsSuiteName)
  }

  func testImportsAnAudioFileAndKeepsBothNameCollisions() throws {
    let source = root.appendingPathComponent("song.mp3")
    try Data("audio".utf8).write(to: source)
    let store = makeStore()

    let first = store.importURL(source)
    let second = store.importURL(source)

    XCTAssertEqual(first.copiedCount, 1)
    XCTAssertEqual(second.copiedCount, 1)
    XCTAssertTrue(fileExists("Music/song.mp3"))
    XCTAssertTrue(fileExists("Music/song (2).mp3"))
  }

  func testImportsSupportedFilesFromNestedFolders() throws {
    let album = root.appendingPathComponent("source/Album", isDirectory: true)
    let disc = album.appendingPathComponent("Disc 1", isDirectory: true)
    try FileManager.default.createDirectory(
      at: disc,
      withIntermediateDirectories: true
    )
    try Data("audio".utf8).write(
      to: disc.appendingPathComponent("track.flac")
    )
    try Data("notes".utf8).write(
      to: album.appendingPathComponent("notes.txt")
    )

    let receipt = makeStore().importURL(album)

    XCTAssertEqual(receipt.copiedCount, 1)
    XCTAssertEqual(receipt.ignoredCount, 1)
    XCTAssertTrue(fileExists("Music/Album/Disc 1/track.flac"))
    XCTAssertFalse(fileExists("Music/Album/notes.txt"))
  }

  private func makeStore() -> IncomingAudioImportStore {
    IncomingAudioImportStore(
      defaults: defaults,
      documentsDirectory: root
    )
  }

  private func fileExists(_ relativePath: String) -> Bool {
    FileManager.default.fileExists(
      atPath: root.appendingPathComponent(relativePath).path
    )
  }
}
