import Speech

/// 三条 Apple Speech 识别路径共用配置，避免实时识别行为不一致。
enum DefaultAppleSpeechRequestFactory {
    enum Route: String, Sendable, Equatable {
        case audioBuffer
        case fileURL
        case unknown

        init(label: String?) {
            guard let label else {
                self = .unknown
                return
            }

            switch label.lowercased() {
            case "audio", "buffer", "audio_buffer", "audio-buffer", "live":
                self = .audioBuffer
            case "file", "fileurl", "file_url", "file-url", "url":
                self = .fileURL
            default:
                self = .unknown
            }
        }
    }

    static func makeRequest(for route: Route = .audioBuffer) -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // 系统默认关闭自动标点，所有识别路径都需要显式开启。
        if #available(iOS 16, macOS 13, *) {
            request.addsPunctuation = true
        }
        request.requiresOnDeviceRecognition = false
        _ = route
        return request
    }

    static func route(for rawValue: String?) -> Route {
        Route(label: rawValue)
    }

    static func acceptsEquivalentInput(_ lhs: String?, _ rhs: String?) -> Bool {
        let normalized: (String?) -> String? = { value in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return normalized(lhs) == normalized(rhs)
    }
}
