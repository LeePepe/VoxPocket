import Foundation
import Combine
import CoreModels

/// 编辑用例简化实现
///
/// 使用 `CurrentValueSubject` 管理文本状态，
/// 暂不依赖完整的 TextHistory 补丁系统。
public final class DefaultEditingUseCase: EditingUseCase, @unchecked Sendable {

    private let textSubject: CurrentValueSubject<String, Never>

    public var currentText: String { textSubject.value }

    public var currentTextPublisher: AnyPublisher<String, Never> {
        textSubject.eraseToAnyPublisher()
    }

    public init(initialText: String = "") {
        self.textSubject = CurrentValueSubject<String, Never>(initialText)
    }

    public func applyEdit(range: CoreModels.TextRange, newText: String) throws {
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
        textSubject.send(text)
    }

    public func insert(_ text: String, at location: Int) throws {
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
        textSubject.send(textSubject.value + text)
    }

    public func mergeRecentEdits() {
        // 简化实现暂不支持合并
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
