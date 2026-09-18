import Foundation

/// 仅隔离外部 WebSocket I/O，允许测试使用可控的事件流。
protocol RealtimeTranscriptionTransport: Sendable {
    func connect(request: URLRequest) async throws
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close() async
}

actor DefaultRealtimeTranscriptionTransport: RealtimeTranscriptionTransport {
    private var socket: URLSessionWebSocketTask?
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 8
        session = URLSession(configuration: configuration)
    }

    func connect(request: URLRequest) async throws {
        guard socket == nil else { throw RealtimeTranscriptionError.protocolRejected }
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 1_048_576
        socket = task
        task.resume()
    }

    func send(_ data: Data) async throws {
        guard let socket, let text = String(data: data, encoding: .utf8) else {
            throw RealtimeTranscriptionError.connectionFailed
        }
        do { try await socket.send(.string(text)) }
        catch { throw RealtimeTranscriptionError.connectionFailed }
    }

    func receive() async throws -> Data {
        guard let socket else { throw RealtimeTranscriptionError.connectionFailed }
        do {
            switch try await socket.receive() {
            case .data(let data): return data
            case .string(let text): return Data(text.utf8)
            @unknown default: throw RealtimeTranscriptionError.invalidEvent
            }
        } catch { throw RealtimeTranscriptionError.connectionFailed }
    }

    func close() async {
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        session.invalidateAndCancel()
    }
}
