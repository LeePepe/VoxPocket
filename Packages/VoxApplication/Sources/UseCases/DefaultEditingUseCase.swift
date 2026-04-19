import Foundation
import Combine
import CoreModels

/// 编辑用例简化实现
///
/// 使用 `CurrentValueSubject` 管理文本状态，
/// 暂不依赖完整的 TextHistory 补丁系统。
public final class DefaultEditingUseCase: EditingUseCase, @unchecked Sendable {

    private let textSubject: CurrentValueSubject<String, Never>

    // MARK: - 语音区域状态

    private var _voiceAnchorLocation: Int? = nil
    private var _isVoiceZoneLocked: Bool = false

    public var currentText: String { textSubject.value }

    public var currentTextPublisher: AnyPublisher<String, Never> {
        textSubject.eraseToAnyPublisher()
    }

    public var voiceAnchorLocation: Int? { _voiceAnchorLocation }
    public var isVoiceZoneLocked: Bool { _isVoiceZoneLocked }

    public init(initialText: String = "") {
        self.textSubject = CurrentValueSubject<String, Never>(initialText)
    }

    // MARK: - Voice Zone API

    public func setVoiceAnchor(_ location: Int) {
        _voiceAnchorLocation = location
    }

    public func clearVoiceAnchor() {
        _voiceAnchorLocation = nil
    }

    public func setVoiceZoneLocked(_ locked: Bool) {
        _isVoiceZoneLocked = locked
    }

    public func replaceVoiceZone(with text: String) throws {
        guard let anchor = _voiceAnchorLocation else {
            throw NSError(domain: "DefaultEditingUseCase", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "语音锚点未设置，无法替换语音区域"])
        }
        let nsString = textSubject.value as NSString
        let anchorClamped = min(anchor, nsString.length)
        let prefix = nsString.substring(to: anchorClamped)
        textSubject.send(prefix + text)
    }

    // MARK: - 编辑操作（含语音区域锁定检查）

    public func applyEdit(range: CoreModels.TextRange, newText: String) throws {
        if _isVoiceZoneLocked && rangeOverlapsVoiceZone(range) {
            throw voiceZoneLockError()
        }
        var text = textSubject.value
        let nsString = text as NSString
        let nsRange = NSRange(location: range.location, length: range.length)

        guard nsRange.location + nsRange.length <= nsString.length else {
            throw NSError(domain: "DefaultEditingUseCase", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "编辑范围超出文本长度"])
        }

        text = nsString.replacingCharacters(in: nsRange, with: newText)
        textSubject.send(text)
    }

    public func replaceAll(with text: String) throws {
        guard !_isVoiceZoneLocked else {
            throw voiceZoneLockError()
        }
        textSubject.send(text)
    }

    public func insert(_ text: String, at location: Int) throws {
        if _isVoiceZoneLocked {
            let anchor = _voiceAnchorLocation ?? Int.max
            if location >= anchor {
                throw voiceZoneLockError()
            }
        }
        var current = textSubject.value
        let nsString = current as NSString
        guard location <= nsString.length else {
            throw NSError(domain: "DefaultEditingUseCase", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "插入位置超出文本长度"])
        }
        current = nsString.inserting(text, at: location)
        textSubject.send(current)
    }

    public func delete(range: CoreModels.TextRange) throws {
        if _isVoiceZoneLocked && rangeOverlapsVoiceZone(range) {
            throw voiceZoneLockError()
        }
        let nsRange = NSRange(location: range.location, length: range.length)
        var text = textSubject.value
        let nsString = text as NSString
        guard nsRange.location + nsRange.length <= nsString.length else {
            throw NSError(domain: "DefaultEditingUseCase", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "删除范围超出文本长度"])
        }
        text = nsString.replacingCharacters(in: nsRange, with: "")
        textSubject.send(text)
    }

    public func append(_ text: String) throws {
        guard !_isVoiceZoneLocked else {
            throw voiceZoneLockError()
        }
        textSubject.send(textSubject.value + text)
    }

    public func mergeRecentEdits() {
        // 简化实现暂不支持合并
    }

    // MARK: - 辅助方法

    private func voiceZoneLockError() -> NSError {
        NSError(
            domain: "DefaultEditingUseCase",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: "语音区域已锁定，无法修改语音区域内容"]
        )
    }

    /// 判断给定范围是否与语音区域（从 anchor 到文本末尾）重叠
    private func rangeOverlapsVoiceZone(_ range: CoreModels.TextRange) -> Bool {
        guard let anchor = _voiceAnchorLocation else { return false }
        return range.location + range.length > anchor
    }
}

// MARK: - NSString helper

private extension NSString {
    func inserting(_ string: String, at index: Int) -> String {
        let mutable = NSMutableString(string: self)
        mutable.insert(string, at: index)
        return mutable as String
    }
}
