import Foundation
import CoreModels

public struct ExternalTodoRemoteSnapshot: Codable, Equatable, Hashable, Sendable {
    public let externalID: String
    public let title: String
    public let executionState: TodoExecutionState
    public let externalURL: String?
    public let teamKey: String
    public let projectName: String?
    public let remoteUpdatedAt: String?

    public init(externalID: String, title: String, executionState: TodoExecutionState, externalURL: String? = nil, teamKey: String = "EXAMPLE", projectName: String? = nil, remoteUpdatedAt: String? = nil) {
        self.externalID = externalID; self.title = title; self.executionState = executionState; self.externalURL = externalURL; self.teamKey = teamKey; self.projectName = projectName; self.remoteUpdatedAt = remoteUpdatedAt
    }
}

public enum TodoExternalSyncError: Error, LocalizedError, Equatable, Sendable {
    case syncDisabled
    case transportUnavailable
    case invalidResponse(String)
    case remoteCommandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .syncDisabled: "External todo sync is disabled"
        case .transportUnavailable: "External todo sync transport is disabled by the sandbox privacy boundary; configure an explicit sync transport handler."
        case .invalidResponse(let detail): "Invalid external todo sync response: \(detail)"
        case .remoteCommandFailed(let detail): "External todo sync command failed: \(detail)"
        }
    }
}

public protocol TodoExternalSyncService: AnyObject, Sendable {
    var isEnabled: Bool { get }
    var isAutoSyncEnabled: Bool { get }
    var configuredTeamKey: String { get }
    func pushTodo(_ todo: VoiceTodo) async throws -> ExternalTodoSyncMetadata
    func fetchRemoteSnapshots() async throws -> [ExternalTodoRemoteSnapshot]
}

public final class NoopTodoExternalSyncService: TodoExternalSyncService, Sendable {
    public let isEnabled: Bool = false
    public let isAutoSyncEnabled: Bool = false
    public let configuredTeamKey: String = "EXAMPLE"

    public init() {}

    public func pushTodo(_ todo: VoiceTodo) async throws -> ExternalTodoSyncMetadata {
        throw TodoExternalSyncError.syncDisabled
    }

    public func fetchRemoteSnapshots() async throws -> [ExternalTodoRemoteSnapshot] {
        []
    }
}

public final class LinearTodoSyncService: TodoExternalSyncService, Sendable {
    public typealias PushTransport = @Sendable (_ todo: VoiceTodo, _ teamKey: String) async throws -> Data
    public typealias PullTransport = @Sendable (_ teamKey: String) async throws -> Data

    public let isEnabled: Bool
    public let isAutoSyncEnabled: Bool
    public let teamKey: String
    public var configuredTeamKey: String { teamKey }
    private let pushTransport: PushTransport?
    private let pullTransport: PullTransport?

    public init(isEnabled: Bool = false, isAutoSyncEnabled: Bool = false, teamKey: String = "EXAMPLE", pushTransport: PushTransport? = nil, pullTransport: PullTransport? = nil) {
        self.isEnabled = isEnabled
        self.isAutoSyncEnabled = isAutoSyncEnabled
        let trimmed = teamKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.teamKey = trimmed.isEmpty ? "EXAMPLE" : trimmed
        self.pushTransport = pushTransport
        self.pullTransport = pullTransport
    }

    public func pushTodo(_ todo: VoiceTodo) async throws -> ExternalTodoSyncMetadata {
        guard isEnabled else { throw TodoExternalSyncError.syncDisabled }
        guard let pushTransport else { throw TodoExternalSyncError.transportUnavailable }
        let targetTeam: String
        if let existing = todo.externalSync, existing.externalID != nil, !existing.teamKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            targetTeam = existing.teamKey
        } else {
            targetTeam = teamKey
        }
        let sanitizedTodo = VoiceTodo(
            id: todo.id,
            title: todo.title,
            taskPrompt: todo.taskPrompt,
            rawTranscript: "",
            projectKey: todo.projectKey,
            assignedRunnerKind: todo.assignedRunnerKind,
            executionState: todo.executionState,
            lastExecutionSummary: nil,
            lastStartedAt: todo.lastStartedAt,
            lastCompletedAt: todo.lastCompletedAt,
            sourceCaptureID: todo.sourceCaptureID,
            localAudioFileName: nil,
            durationSeconds: todo.durationSeconds,
            deviceSource: todo.deviceSource,
            externalSync: todo.externalSync,
            createdAt: todo.createdAt,
            updatedAt: todo.updatedAt
        )
        let data = try await pushTransport(sanitizedTodo, targetTeam)
        return try Self.parsePushResponse(data: data, fallbackTeamKey: targetTeam, existingMetadata: todo.externalSync)
    }

    public func fetchRemoteSnapshots() async throws -> [ExternalTodoRemoteSnapshot] {
        guard isEnabled else { return [] }
        guard let pullTransport else { throw TodoExternalSyncError.transportUnavailable }
        let data = try await pullTransport(teamKey)
        return try Self.parsePullResponse(data: data, teamKey: teamKey)
    }

    public static func mapLinearStateToLocal(state: String?, stateType: String?, labels: [String]) -> TodoExecutionState {
        let blockingLabels: Set<String> = ["Blocked", "Needs Decision", "NEED_GO"]
        let normalizedState = (state ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedType = (stateType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalizedType == "completed" || normalizedType == "canceled" || normalizedType == "cancelled" || normalizedState.caseInsensitiveCompare("Done") == .orderedSame || normalizedState.caseInsensitiveCompare("Canceled") == .orderedSame || normalizedState.caseInsensitiveCompare("Cancelled") == .orderedSame {
            return .done
        }
        if labels.contains(where: { blockingLabels.contains($0) }) {
            return .failed
        }
        if normalizedState.caseInsensitiveCompare("In Progress") == .orderedSame || normalizedState.caseInsensitiveCompare("In Review") == .orderedSame || normalizedType == "started" {
            return .running
        }
        return .inbox
    }

    public static func mapLocalStateToLinearState(_ state: TodoExecutionState) -> String {
        switch state {
        case .inbox: "Todo"
        case .running: "In Progress"
        case .done: "Done"
        case .failed: "Todo"
        }
    }

    public static func parsePushResponse(data: Data, fallbackTeamKey: String = "EXAMPLE", existingMetadata: ExternalTodoSyncMetadata? = nil) throws -> ExternalTodoSyncMetadata {
        let envelope: LinearCommandEnvelope
        do {
            envelope = try JSONDecoder().decode(LinearCommandEnvelope.self, from: data)
        } catch {
            throw TodoExternalSyncError.invalidResponse("malformed JSON payload")
        }
        guard envelope.ok != false else {
            throw TodoExternalSyncError.remoteCommandFailed(envelope.error ?? "remote command returned ok=false")
        }
        guard let issue = envelope.issue else {
            throw TodoExternalSyncError.invalidResponse("missing issue object")
        }
        let identifier = issue.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else {
            throw TodoExternalSyncError.invalidResponse("empty issue identifier")
        }
        let resolvedTeam = Self.extractTeamKey(from: identifier) ?? fallbackTeamKey
        return ExternalTodoSyncMetadata(
            provider: "linear",
            externalID: identifier,
            externalURL: issue.url ?? existingMetadata?.externalURL,
            teamKey: resolvedTeam,
            projectName: issue.project ?? existingMetadata?.projectName,
            syncState: .synced,
            remoteUpdatedAt: issue.updatedAt ?? existingMetadata?.remoteUpdatedAt,
            lastError: nil
        )
    }

    public static func parsePullResponse(data: Data, teamKey: String = "EXAMPLE") throws -> [ExternalTodoRemoteSnapshot] {
        let envelope: LinearListIssuesEnvelope
        do {
            envelope = try JSONDecoder().decode(LinearListIssuesEnvelope.self, from: data)
        } catch {
            throw TodoExternalSyncError.invalidResponse("malformed list-issues JSON payload")
        }
        guard envelope.ok != false else {
            throw TodoExternalSyncError.remoteCommandFailed(envelope.error ?? "list-issues returned ok=false")
        }
        let issues = envelope.issues ?? []
        var deduplicated: [String: ExternalTodoRemoteSnapshot] = [:]
        var orderedIDs: [String] = []
        for issue in issues {
            let identifier = issue.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty else { continue }
            let state = Self.mapLinearStateToLocal(state: issue.state, stateType: issue.stateType, labels: issue.labels ?? [])
            let resolvedTeam = Self.extractTeamKey(from: identifier) ?? teamKey
            let candidate = ExternalTodoRemoteSnapshot(
                externalID: identifier,
                title: issue.title,
                executionState: state,
                externalURL: issue.url,
                teamKey: resolvedTeam,
                projectName: issue.project,
                remoteUpdatedAt: issue.updatedAt
            )
            if let existing = deduplicated[identifier] {
                if (candidate.remoteUpdatedAt ?? "") >= (existing.remoteUpdatedAt ?? "") {
                    deduplicated[identifier] = candidate
                }
            } else {
                orderedIDs.append(identifier)
                deduplicated[identifier] = candidate
            }
        }
        return orderedIDs.compactMap { deduplicated[$0] }
    }

    private static func extractTeamKey(from identifier: String) -> String? {
        guard let prefix = identifier.split(separator: "-").first, !prefix.isEmpty else { return nil }
        return String(prefix)
    }
}

private struct LinearCommandEnvelope: Decodable {
    let ok: Bool?
    let command: String?
    let error: String?
    let issue: LinearIssueDTO?
}

private struct LinearListIssuesEnvelope: Decodable {
    let ok: Bool?
    let command: String?
    let error: String?
    let issues: [LinearIssueDTO]?
}

private struct LinearIssueDTO: Decodable {
    let id: String?
    let identifier: String
    let title: String
    let state: String?
    let stateType: String?
    let project: String?
    let priority: Int?
    let url: String?
    let createdAt: String?
    let updatedAt: String?
    let labels: [String]?
}
