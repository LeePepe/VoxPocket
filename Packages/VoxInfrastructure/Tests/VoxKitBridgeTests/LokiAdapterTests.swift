import Foundation
import LokiKit
import Synchronization
import VoxCore
import VoxKitBridge
import XCTest

final class LokiAdapterTests: XCTestCase {
    func testLoggerForwardsLevelMessageAndEveryTypedField() {
        let destination = AdapterLogger()
        let logger = LokiVoxLogger(logger: destination)
        logger.warning("synthetic event", fields: [.int("count", 3), .bool("enabled", true), .label("provider", .provider("whisperkit"))])
        let entries = destination.entries.withLock { $0 }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.level, .warning)
        XCTAssertEqual(entries.first?.message, "synthetic event")
        XCTAssertEqual(entries.first?.fields, ["count": "3", "enabled": "true", "provider": "whisperkit"])
    }

    func testTelemetryForwardsStaticEventAndTypedMetrics() {
        let destination = AdapterTelemetry()
        let telemetry = LokiVoxTelemetry(service: destination)
        telemetry.record(VoxTelemetryEvent(name: "synthetic.completed", fields: [.int("count", 2), .label("source", .source("whisperKit"))]))
        let events = destination.events.withLock { $0 }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.name, "synthetic.completed")
        XCTAssertEqual(events.first?.properties, ["count": "2", "source": "whisperKit"])
    }
}

private final class AdapterLogger: Logger {
    struct Entry: Sendable {
        let level: LogLevel
        let message: String
        let fields: [String: String]
    }
    let entries = Mutex<[Entry]>([])
    private let level = Mutex(LogLevel.debug)
    var minimumLevel: LogLevel {
        get { level.withLock { $0 } }
        set { level.withLock { $0 = newValue } }
    }
    func log(_ level: LogLevel, _ message: @autoclosure () -> String, file: String, function: String, line: Int) {
        entries.withLock { $0.append(Entry(level: level, message: message(), fields: [:])) }
    }
    func log(_ level: LogLevel, _ message: @autoclosure () -> String, context: [String: Any], file: String, function: String, line: Int) {
        entries.withLock { $0.append(Entry(level: level, message: message(), fields: context.mapValues { String(describing: $0) })) }
    }
}

private final class AdapterTelemetry: TelemetryService {
    let events = Mutex<[TelemetryEvent]>([])
    private let enabled = Mutex(true)
    var isEnabled: Bool {
        get { enabled.withLock { $0 } }
        set { enabled.withLock { $0 = newValue } }
    }
    func track(_ event: TelemetryEvent) { events.withLock { $0.append(event) } }
    func track(name: String, properties: [String: String]) { track(TelemetryEvent(name: name, properties: properties)) }
    func flush() async {}
    func resetIdentifier() {}
}
