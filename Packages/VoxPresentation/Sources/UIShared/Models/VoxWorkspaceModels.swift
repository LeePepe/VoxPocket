import Foundation
import CoreModels

public enum TodoStatusFilter: String, CaseIterable, Sendable {
    case all, inbox, running, done, failed
}

public enum WorkspaceSortOrder: Sendable {
    case newestFirst
    case oldestFirst
}

public enum WorkspaceSidebarSection: Equatable, Sendable {
    case todoInbox, todoRunning, todoDone, todoAll, voiceNotes, project(String)
}
