import XCTest
import Combine
import Foundation
import Synchronization
import VoxCore
import TranscriptionKitCombine
@testable import TranscriptionKit

let testStorageLocations = VoxStorageLocations(
    temporaryAudio: FileManager.default.temporaryDirectory.appendingPathComponent("example-audio", isDirectory: true),
    modelCache: FileManager.default.temporaryDirectory.appendingPathComponent("example-models", isDirectory: true))


func assertEventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !predicate(), ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertTrue(predicate(), "Expected async event delivery", file: file, line: line)
}
