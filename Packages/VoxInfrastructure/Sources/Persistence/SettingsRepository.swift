import Foundation
import Combine

/// 设置键定义
public enum SettingsKey: String, CaseIterable, Sendable {
    // ASR 设置
    case asrProvider = "asr.provider"
    case transcriptionLanguage = "asr.language"

    // LLM 设置
    case llmProvider = "llm.provider"
    case llmAPIKey = "llm.apiKey"
    case llmModelIdentifier = "llm.modelIdentifier"
    case llmBaseURL = "llm.baseURL"

    // macOS 设置
    case globalHotkey = "macos.globalHotkey"
    case showInMenuBar = "macos.showInMenuBar"
    case useAccessibilityAPI = "macos.useAccessibilityAPI"

    // 通用设置
    case theme = "general.theme"
    case autoSave = "general.autoSave"
    case autoSaveInterval = "general.autoSaveInterval"
}

/// 用户设置仓储协议
///
/// 负责用户偏好设置的持久化。
public protocol SettingsRepository: AnyObject, Sendable {

    /// 获取设置值
    ///
    /// - Parameter key: 设置键
    /// - Returns: 设置值，如果不存在则返回 nil
    func getValue<T: Codable>(for key: SettingsKey) -> T?

    /// 获取设置值（带默认值）
    ///
    /// - Parameters:
    ///   - key: 设置键
    ///   - defaultValue: 默认值
    /// - Returns: 设置值或默认值
    func getValue<T: Codable>(for key: SettingsKey, default defaultValue: T) -> T

    /// 设置值
    ///
    /// - Parameters:
    ///   - value: 要设置的值
    ///   - key: 设置键
    func setValue<T: Codable>(_ value: T, for key: SettingsKey)

    /// 移除设置值
    ///
    /// - Parameter key: 设置键
    func removeValue(for key: SettingsKey)

    /// 观察设置变化
    ///
    /// - Parameter key: 设置键
    /// - Returns: 发布设置值变化的发布者
    func observe<T: Codable>(key: SettingsKey) -> AnyPublisher<T?, Never>

    /// 重置所有设置为默认值
    func resetAll()
}
