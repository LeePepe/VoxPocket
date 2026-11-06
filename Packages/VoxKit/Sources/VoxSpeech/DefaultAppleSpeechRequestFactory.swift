import VoxCore
import Speech

/// 三条 Apple Speech 识别路径共用配置，避免实时识别行为不一致。
public enum DefaultAppleSpeechRequestFactory {
    public static func makeRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // 系统默认关闭自动标点，所有识别路径都需要显式开启。
        if #available(iOS 16, macOS 13, *) {
            request.addsPunctuation = true
        }
        request.requiresOnDeviceRecognition = false
        return request
    }
}
