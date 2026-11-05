import TranscriptionKitCombine
import VoxCore
import CoreFoundation
import Foundation
import LokiKit
import Synchronization
import XCTest

final class GoldenEvents: Sendable {
    private let storage = Mutex<[String]>([])
    func append(_ value: String) { storage.withLock { $0.append(value) } }
    var values: [String] { storage.withLock { $0 } }
}

final class GoldenLogger: Logger, VoxLogger, Sendable {
    private let level = Mutex(LogLevel.debug)
    private let events = GoldenEvents()
    private let keys = Mutex<[[String]]>([])
    var minimumLevel: LogLevel {
        get { level.withLock { $0 } }
        set { level.withLock { $0 = newValue } }
    }
    func log(_ level: VoxLogLevel, _ message: StaticString, fields: [VoxLogField]) {
        let context = Dictionary(fields.map { (String(describing: $0.key), $0.value.text as Any) }, uniquingKeysWith: { _, latest in latest })
        log(LogLevel.info, String(describing: message), context: context, file: #file, function: #function, line: #line)
    }
    var messages: [String] { events.values }
    var contextKeys: [[String]] { keys.withLock { $0 } }
    func log(_ level: LogLevel, _ message: @autoclosure () -> String,
             file: String, function: String, line: Int) {
        log(level, message(), context: [:], file: file, function: function, line: line)
    }
    func log(_ level: LogLevel, _ message: @autoclosure () -> String,
             context: [String: Any], file: String, function: String, line: Int) {
        let value = message()
        let allowed: Set<String> = [
            "Initialized", "Applied LLM analysis settings", "Configured LLM provider", "No audio file",
            "Already transcribing, stopping first", "Recording + Apple Speech started", "Merging Apple Speech + Whisper via LLM",
            "开始内容分析", "内容分析完成", "开始文本优化", "文本优化完成",
            "开始流式文本优化", "流式文本优化完成", "流式文本优化失败"
        ]
        let allowedKeys: Set<String> = ["duration_ms", "char_count", "call_count", "input_length", "output_length",
                                        "text_length", "transcription_length", "refined_length", "length", "count",
                                        "error_code", "status", "elapsed_ms", "retry_count"]
        if allowed.contains(value) {
            events.append(value)
            keys.withLock { $0.append(context.keys.filter { allowedKeys.contains($0) }.sorted()) }
        }
    }
}

func assertGolden(_ payload: [String: Any], name: String,
                  file: StaticString = #filePath, line: UInt = #line) throws {
    let data = try GoldenFixtureCodec.encode(payload)
    if let directory = ProcessInfo.processInfo.environment["VOX_GOLDEN_RECORD_DIR"] {
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".json"))
    }
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    let expected = try GoldenFixtureCodec.decode(Data(contentsOf: url))
    XCTAssertEqual(payload as NSDictionary, expected, file: file, line: line)
}

private enum GoldenFixtureCodec {
    static func encode(_ payload: [String: Any]) throws -> Data {
        var values: [Any] = []
        var indices: [Data: Int] = [:]
        func intern(_ value: Any) throws -> Int {
            let node: Any
            if let object = value as? [String: Any] {
                var references: [String: Int] = [:]
                for key in object.keys.sorted() { references[key] = try intern(object[key]!) }
                node = references
            } else if let array = value as? [Any] {
                node = try array.map(intern)
            } else {
                node = value
            }
            let key = try JSONSerialization.data(withJSONObject: node, options: [.sortedKeys, .fragmentsAllowed])
            if let index = indices[key] { return index }
            let index = values.count
            values.append(node)
            indices[key] = index
            return index
        }
        let root = try intern(payload)
        return try JSONSerialization.data(withJSONObject: [
            "schema": "golden-trace/v1", "encoding": "interned-values/v1", "root": root, "values": values
        ], options: [.sortedKeys])
    }

    static func decode(_ data: Data) throws -> NSDictionary {
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              envelope["schema"] as? String == "golden-trace/v1" else { throw CocoaError(.coderReadCorrupt) }
        guard envelope["encoding"] != nil else { return envelope as NSDictionary }
        guard envelope["encoding"] as? String == "interned-values/v1",
              let values = envelope["values"] as? [Any], let root = envelope["root"] else {
            throw CocoaError(.coderReadCorrupt)
        }
        var expanded: [Any] = []
        func resolve(_ reference: Any) throws -> Any {
            guard let number = reference as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let index = reference as? Int, expanded.indices.contains(index) else {
                throw CocoaError(.coderReadCorrupt)
            }
            return expanded[index]
        }
        for node in values {
            let value: Any
            if let object = node as? [String: Any] {
                value = try object.mapValues(resolve)
            } else if let array = node as? [Any] {
                value = try array.map(resolve)
            } else {
                value = node
            }
            expanded.append(value)
        }
        guard let payload = try resolve(root) as? NSDictionary else { throw CocoaError(.coderReadCorrupt) }
        return payload
    }
}

final class GoldenFixtureCodecTests: XCTestCase {
    func testPackedAndExpandedFixturesPreserveJSONValues() throws {
        let payload: [String: Any] = ["schema": "golden-trace/v1", "kind": "codec", "traces": [
            ["emptyObject": [String: Any](), "emptyArray": [Any](), "null": NSNull(),
             "numbers": [0, 1, -1, 0.5], "booleans": [true, false], "text": "synthetic\n原文",
             "repeated": [["key": "synthetic"], ["key": "synthetic"]]]
        ]]
        let expected = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        for data in [try GoldenFixtureCodec.encode(payload), expected] {
            let actual = try GoldenFixtureCodec.decode(data)
            XCTAssertEqual(actual, payload as NSDictionary)
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: actual, options: [.sortedKeys]), expected)
        }
    }

    func testMalformedPackedFixturesFailClosed() throws {
        for reference: Any in [-1, 1, true, "0"] {
            let data = try JSONSerialization.data(withJSONObject: [
                "schema": "golden-trace/v1", "encoding": "interned-values/v1", "root": 0,
                "values": [["invalid": reference]]
            ])
            XCTAssertThrowsError(try GoldenFixtureCodec.decode(data))
        }
    }
}
