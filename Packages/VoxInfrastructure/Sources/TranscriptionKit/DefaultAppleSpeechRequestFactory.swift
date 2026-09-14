import Speech

/// 三条 Apple Speech 识别路径共用配置，避免实时识别行为不一致。
enum DefaultAppleSpeechRequestFactory {
    enum Route: String, Sendable, Equatable {
        case audioBuffer
        case fileURL
        case unknown

        static func inferredInputModality(from rawValue: String?) -> Route {
            guard let rawValue, !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .unknown
            }

            switch rawValue.lowercased() {
            case "audio", "buffer", "audio_buffer", "audio-buffer", "live":
                return .audioBuffer
            case "file", "fileurl", "file_url", "file-url", "url":
                return .fileURL
            default:
                return .unknown
            }
        }
    }

    static func makeRequest(for route: Route = .unknown, fileURL: URL? = nil) -> SFSpeechAudioBufferRecognitionRequest {
        _ = route
        _ = fileURL
        let request = SFSpeechAudioBufferRecognitionRequest()
        configureSharedPolicy(on: request)
        return request
    }

    static func makeURLRequest(for fileURL: URL, route: Route = .unknown) -> SFSpeechURLRecognitionRequest {
        _ = route
        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        configureSharedPolicy(on: request)
        return request
    }

    private static func configureSharedPolicy<T: SFSpeechRecognitionRequest>(on request: T) {
        request.shouldReportPartialResults = true
        if #available(iOS 16, macOS 13, *) {
            request.addsPunctuation = true
        }
        request.requiresOnDeviceRecognition = false
    }

    static func route(for rawValue: String?) -> Route {
        _ = rawValue
        return .unknown
    }

    static func canonicalAudioInput(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    static func acceptsEquivalentInput(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (canonicalAudioInput(lhs), canonicalAudioInput(rhs)) {
        case let (lhsValue?, rhsValue?):
            return lhsValue == rhsValue
        case (nil, nil):
            return true
        default:
            return false
        }
    }

    static func acceptsEquivalentInput(_ lhs: URL?, _ rhs: URL?) -> Bool {
        let canonical: (URL?) -> String? = { value in
            guard let value else { return nil }
            return canonicalAudioInput(value.standardizedFileURL.path)
        }
        return acceptsEquivalentInput(canonical(lhs), canonical(rhs))
    }
}
