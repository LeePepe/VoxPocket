import Foundation

/// 一次录音一个 session。调用方串行提供 PCM；服务器文本仅经回调/返回值传出，不进入日志。
actor DefaultRealtimeTranscriptionSession {
    private enum Phase { case idle, configuring, streaming, finishing, completed, failed }
    private let config: AzureRealtimeTranscriptionConfig
    private let transport: any RealtimeTranscriptionTransport
    private let onPartial: @Sendable (String) -> Void
    private let timeout: Duration
    private var phase: Phase = .idle
    private var failure: RealtimeTranscriptionError?
    private var receiver: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var readyWaiters: [CheckedContinuation<Void, Error>] = []
    private var finalWaiters: [CheckedContinuation<String, Error>] = []
    private var transcript = RealtimeTranscriptBuffer()
    private var audioBytes = 0
    private var output: String?

    init(config: AzureRealtimeTranscriptionConfig,
         transport: any RealtimeTranscriptionTransport = DefaultRealtimeTranscriptionTransport(),
         timeout: Duration = .seconds(8), onPartial: @escaping @Sendable (String) -> Void) {
        self.config = config
        self.transport = transport
        self.timeout = timeout
        self.onPartial = onPartial
    }

    func open(language: String) async throws {
        guard phase == .idle else { throw RealtimeTranscriptionError.protocolRejected }
        phase = .configuring
        armDeadline()
        do {
            try await transport.connect(request: config.request())
            startReceiver()
            try await send([
                "type": "session.update",
                "session": ["type": "transcription", "audio": ["input": [
                    "format": ["type": "audio/pcm", "rate": 24000],
                    "turn_detection": NSNull(),
                    "transcription": ["model": config.deployment, "language": language, "delay": "medium"]
                ]]]
            ])
            try await waitUntilReady()
        } catch {
            let safeError = failure ?? (error as? RealtimeTranscriptionError) ?? .connectionFailed
            await fail(safeError)
            throw safeError
        }
    }

    func append(_ pcm: Data) async throws {
        guard phase == .streaming else { throw failure ?? RealtimeTranscriptionError.protocolRejected }
        guard !pcm.isEmpty, pcm.count.isMultiple(of: 2), pcm.count <= 65_536 else {
            throw RealtimeTranscriptionError.unsupportedAudio
        }
        audioBytes += pcm.count
        do { try await send(["type": "input_audio_buffer.append", "audio": pcm.base64EncodedString()]) }
        catch { await fail(.connectionFailed); throw failure ?? RealtimeTranscriptionError.connectionFailed }
    }

    func finish() async throws -> String {
        if let output { return output }
        if let failure { throw failure }
        guard phase == .streaming || phase == .finishing else { throw RealtimeTranscriptionError.protocolRejected }
        if phase == .streaming {
            guard audioBytes >= 4800 else { await fail(.emptyTranscript); throw RealtimeTranscriptionError.emptyTranscript }
            phase = .finishing
            armDeadline()
            do { try await send(["type": "input_audio_buffer.commit"]) }
            catch { await fail(.connectionFailed) }
        }
        return try await withCheckedThrowingContinuation { continuation in
            if let output { continuation.resume(returning: output) }
            else if let failure { continuation.resume(throwing: failure) }
            else { finalWaiters.append(continuation) }
        }
    }

    func cancel() async { await fail(.cancelled) }

    private func send(_ object: [String: Any]) async throws {
        let data: Data
        do { data = try JSONSerialization.data(withJSONObject: object) }
        catch { throw RealtimeTranscriptionError.invalidEvent }
        try await transport.send(data)
    }

    private func startReceiver() {
        let transport = self.transport
        receiver = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let data = try await transport.receive()
                    guard let self else { return }
                    try await self.receive(data)
                }
            } catch { await self?.fail((error as? RealtimeTranscriptionError) ?? .connectionFailed) }
        }
    }

    private func receive(_ data: Data) async throws {
        guard phase != .completed, phase != .failed else { return }
        guard data.count <= 1_048_576,
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { throw RealtimeTranscriptionError.invalidEvent }
        switch type {
        case "session.updated":
            guard phase == .configuring else { return }
            phase = .streaming
            deadline?.cancel(); deadline = nil
            let waiters = readyWaiters; readyWaiters.removeAll()
            waiters.forEach { $0.resume() }
        case "error", "conversation.item.input_audio_transcription.failed":
            throw RealtimeTranscriptionError.protocolRejected
        case "input_audio_buffer.committed":
            guard phase == .finishing, let id = event["item_id"] as? String else {
                throw RealtimeTranscriptionError.invalidEvent
            }
            try transcript.commit(itemID: id)
        case "conversation.item.input_audio_transcription.delta":
            guard let id = event["item_id"] as? String, let delta = event["delta"] as? String else {
                throw RealtimeTranscriptionError.invalidEvent
            }
            try transcript.append(itemID: id, delta: delta)
            onPartial(transcript.partialText)
        case "conversation.item.input_audio_transcription.completed":
            guard let id = event["item_id"] as? String, let text = event["transcript"] as? String else {
                throw RealtimeTranscriptionError.invalidEvent
            }
            try transcript.complete(itemID: id, text: text)
            onPartial(transcript.partialText)
        default: break
        }
        await finishIfComplete()
    }

    private func finishIfComplete() async {
        guard phase == .finishing, transcript.commitCount == 1, let final = transcript.finalText else { return }
        guard !final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { await fail(.emptyTranscript); return }
        output = final
        phase = .completed
        deadline?.cancel(); deadline = nil
        receiver?.cancel(); receiver = nil
        let waiters = finalWaiters; finalWaiters.removeAll()
        waiters.forEach { $0.resume(returning: final) }
        await transport.close()
    }

    private func waitUntilReady() async throws {
        try await withCheckedThrowingContinuation { continuation in
            if phase == .streaming { continuation.resume() }
            else if let failure { continuation.resume(throwing: failure) }
            else { readyWaiters.append(continuation) }
        }
    }

    private func armDeadline() {
        deadline?.cancel()
        let timeout = self.timeout
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            await self?.fail(.timeout)
        }
    }

    private func fail(_ error: RealtimeTranscriptionError) async {
        guard phase != .completed, phase != .failed else { return }
        phase = .failed; failure = error
        deadline?.cancel(); deadline = nil
        receiver?.cancel(); receiver = nil
        let ready = readyWaiters; readyWaiters.removeAll()
        let final = finalWaiters; finalWaiters.removeAll()
        ready.forEach { $0.resume(throwing: error) }
        final.forEach { $0.resume(throwing: error) }
        await transport.close()
    }
}
