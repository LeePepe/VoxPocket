// VoxPerformanceMonitor.swift
// VoxPocket 性能测试辅助工具
// 封装 XCTest 性能度量，并提供简易帧率跟踪

import Foundation
#if canImport(XCTest)
import XCTest
#endif

#if canImport(QuartzCore)
import QuartzCore
#endif

// MARK: - 性能度量选项

/// 待测量的 VoxPocket 操作类型
public enum VoxOperation: String, Sendable {
    /// 启动录音（点击 → AVAudioSession 就绪）
    case startRecording   = "StartRecording"
    /// 停止录音（触发 → 最终转录完成）
    case stopRecording    = "StopRecording"
    /// 转录文本显示（音频送入 → 首字出现）
    case firstTranscript  = "FirstTranscript"
    /// LLM 润色（请求 → 首 token 到达）
    case firstRefinement  = "FirstRefinement"
    /// 会话列表加载（视图出现 → 列表渲染完毕）
    case sessionListLoad  = "SessionListLoad"
}

// MARK: - 帧率样本

/// 单次帧时间样本
public struct FrameSample: Sendable {
    /// 时间戳（秒，相对于采集开始）
    public let timestamp: TimeInterval
    /// 与上一帧间隔（秒）
    public let frameDuration: TimeInterval

    public init(timestamp: TimeInterval, frameDuration: TimeInterval) {
        self.timestamp = timestamp
        self.frameDuration = frameDuration
    }

    /// 换算为帧率（fps）
    public var fps: Double { 1.0 / max(frameDuration, 0.0001) }
}

// MARK: - 帧率追踪器

/// 基于 CADisplayLink / CVDisplayLink 的简易帧率追踪
/// 在不支持的平台上退化为时间戳模拟
public final class VoxFrameTracker: @unchecked Sendable {
    private var samples: [FrameSample] = []
    private var startTime: CFTimeInterval = 0
    private var lastTimestamp: CFTimeInterval = 0
    private var isTracking = false

    private var displayLink: CADisplayLink?

    public init() {}

    deinit { stop() }

    // MARK: 公共控制

    /// 开始采集帧时间
    public func start() {
        guard !isTracking else { return }
        samples.removeAll()
        startTime = CACurrentMediaTime()
        lastTimestamp = startTime
        isTracking = true
        startDisplayLink()
    }

    /// 停止采集并返回所有样本
    @discardableResult
    public func stop() -> [FrameSample] {
        guard isTracking else { return samples }
        isTracking = false
        stopDisplayLink()
        return samples
    }

    /// 统计：平均帧率
    public var averageFPS: Double {
        guard samples.count > 1 else { return 0 }
        let total = samples.reduce(0.0) { $0 + $1.frameDuration }
        return Double(samples.count) / total
    }

    /// 统计：最低帧率（最大帧时间）
    public var minimumFPS: Double {
        guard let worst = samples.max(by: { $0.frameDuration < $1.frameDuration }) else { return 0 }
        return worst.fps
    }

    /// 统计：掉帧数（帧时间超过 33.3ms，即低于 30fps）
    public var droppedFrameCount: Int {
        samples.filter { $0.frameDuration > 1.0 / 30.0 }.count
    }

    // MARK: 内部 DisplayLink 实现

    private func recordFrame(timestamp: CFTimeInterval) {
        guard isTracking else { return }
        let elapsed = timestamp - startTime
        let delta   = timestamp - lastTimestamp
        lastTimestamp = timestamp
        let sample = FrameSample(timestamp: elapsed, frameDuration: delta)
        samples.append(sample)
    }

    private func startDisplayLink() {
        #if os(macOS)
        // macOS 14+: CADisplayLink 通过 NSScreen 创建
        let link = NSScreen.main?.displayLink(target: self, selector: #selector(handleFrame(_:)))
        link?.add(to: .main, forMode: .common)
        displayLink = link
        #else
        let link = CADisplayLink(target: self, selector: #selector(handleFrame(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        #endif
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func handleFrame(_ link: CADisplayLink) {
        recordFrame(timestamp: link.timestamp)
    }
}

// MARK: - VoxPerformanceMonitor

/// XCTest 性能度量封装
public enum VoxPerformanceMonitor {

    // MARK: 操作计时

    /// 测量指定 VoxPocket 操作的执行时间（毫秒）
    ///
    /// - Parameters:
    ///   - operation: 操作类型（用于报告命名）
    ///   - iterations: 重复次数，取平均值
    ///   - block:      异步操作体
    /// - Returns: 平均执行时长（秒）
    public static func measure(
        operation: VoxOperation,
        iterations: Int = 5,
        block: @escaping () async throws -> Void
    ) async throws -> TimeInterval {
        var durations: [TimeInterval] = []

        for _ in 0..<iterations {
            let start = CACurrentMediaTime()
            try await block()
            let end = CACurrentMediaTime()
            durations.append(end - start)
        }

        let average = durations.reduce(0, +) / Double(durations.count)
        print("[VoxPerf] \(operation.rawValue): avg=\(String(format: "%.3f", average * 1000))ms over \(iterations) runs")
        return average
    }

    // MARK: XCTest 度量集成（仅在 XCTest 可用时编译）

    #if canImport(XCTest)
    /// 在 XCTest `measure` 块中运行标准操作度量
    ///
    /// - Parameters:
    ///   - testCase: 当前测试用例
    ///   - operation: 操作类型
    ///   - metrics:   使用的度量列表（默认：时间 + 内存）
    ///   - block:     同步操作体
    public static func measureInTest(
        _ testCase: XCTestCase,
        operation: VoxOperation,
        metrics: [XCTMetric] = [XCTClockMetric(), XCTMemoryMetric()],
        block: @escaping () -> Void
    ) {
        testCase.measure(metrics: metrics, block: block)
    }

    // MARK: 阈值断言

    /// 断言操作执行时间在给定阈值内
    public static func assertWithinThreshold(
        duration: TimeInterval,
        threshold: TimeInterval,
        operation: VoxOperation,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertLessThanOrEqual(
            duration,
            threshold,
            "\(operation.rawValue) 耗时 \(String(format: "%.0f", duration * 1000))ms，超出阈值 \(String(format: "%.0f", threshold * 1000))ms",
            file: file,
            line: line
        )
    }

    // MARK: 帧率断言

    /// 断言平均帧率高于指定 fps
    public static func assertFrameRate(
        tracker: VoxFrameTracker,
        minimumAverageFPS: Double = 55.0,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let avg = tracker.averageFPS
        XCTAssertGreaterThanOrEqual(
            avg,
            minimumAverageFPS,
            "平均帧率 \(String(format: "%.1f", avg)) fps 低于最低要求 \(minimumAverageFPS) fps",
            file: file,
            line: line
        )
    }
    #endif // canImport(XCTest)
}
