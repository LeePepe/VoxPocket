import SwiftUI

struct RawTranscriptView: View {
    let rawText: String
    let status: RecorderStatus
    let canCopyRaw: Bool
    let onCopyRaw: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        rawText: String,
        status: RecorderStatus = .idle,
        canCopyRaw: Bool? = nil,
        onCopyRaw: @escaping () -> Void = {}
    ) {
        self.rawText = rawText
        self.status = status
        self.canCopyRaw = canCopyRaw ?? !rawText.isEmpty
        self.onCopyRaw = onCopyRaw
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(rawText.isEmpty ? "暂无原始转写内容。" : rawText)
                    .font(.custom("Avenir Next", size: 16))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .background(BackgroundAtmosphere(status: status))
            .navigationTitle("Raw Transcript")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy Raw", action: onCopyRaw)
                        .disabled(!canCopyRaw)
                        .opacity(canCopyRaw ? 1 : 0.4)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    RawTranscriptView(rawText: "原始转写示例内容。\n这里是第二行。", status: .listening)
}
