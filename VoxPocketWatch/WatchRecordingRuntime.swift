import Foundation

@MainActor
enum WatchRecordingRuntime {
    private static var startAction: (@MainActor () -> Void)?
    private static var pendingStart = false
    static func install(start: @escaping @MainActor () -> Void) {
        startAction = start
        if pendingStart { pendingStart = false; start() }
    }
    static func start() {
        guard let startAction else { pendingStart = true; return }
        startAction()
    }
    static func open(_ url: URL) {
        guard url.scheme == "voxpocket-watch", url.host == "record", url.path.isEmpty,
              url.query == nil, url.fragment == nil, url.user == nil, url.password == nil else { return }
        start()
    }
}
