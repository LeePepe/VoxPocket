import Foundation
import CoreModels

public enum TodoStatusFilter: String, CaseIterable, Sendable {
    case all, inbox, running, done, failed
}

public enum WorkspacePage: Int, CaseIterable, Equatable, Hashable, Sendable {
    case recorder = 0
    case todo = 1
}

public enum WorkspaceSortOrder: Sendable {
    case newestFirst
    case oldestFirst
}

public enum WorkspaceSidebarSection: Equatable, Hashable, Sendable {
    case todoInbox, todoRunning, todoDone, todoAll, voiceNotes, project(String)
}
