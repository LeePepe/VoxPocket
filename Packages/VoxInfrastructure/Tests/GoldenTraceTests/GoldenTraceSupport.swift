import Foundation
import LokiKit
import Synchronization
import XCTest

final class GoldenEvents: Sendable {
    private let storage = Mutex<[String]>([])
    func append(_ value: String) { storage.withLock { $0.append(value) } }
    var values: [String] { storage.withLock { $0 } }
}

final class GoldenLogger: Logger, Sendable {
    private let level = Mutex(LogLevel.debug)
    private let events = GoldenEvents()
    private let keys = Mutex<[[String]]>([])
    var minimumLevel: LogLevel {
        get { level.withLock { $0 } }
        set { level.withLock { $0 = newValue } }
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
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .prettyPrinted])
    if let directory = ProcessInfo.processInfo.environment["VOX_GOLDEN_RECORD_DIR"] {
        try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".json"))
    }
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? NSDictionary
    XCTAssertEqual(payload as NSDictionary, expected, file: file, line: line)
}
