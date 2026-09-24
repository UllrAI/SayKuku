import Foundation
import Testing
@testable import SayKuku

@Suite("Qwen request contracts")
struct QwenRequestContractTests {
    @Test("only short-lived network failures are retried")
    func retryPolicy() {
        #expect(QwenReasoningClient.isRetryableNetworkError(URLError(.networkConnectionLost)))
        #expect(QwenReasoningClient.isRetryableNetworkError(URLError(.cannotConnectToHost)))
        #expect(!QwenReasoningClient.isRetryableNetworkError(URLError(.timedOut)))
        #expect(!QwenReasoningClient.isRetryableNetworkError(URLError(.notConnectedToInternet)))
    }

    @Test("realtime failures fall back to batch recognition only for transient errors")
    func batchFallbackPolicy() {
        #expect(QwenError.allowsBatchFallback(after: URLError(.networkConnectionLost)))
        #expect(QwenError.allowsBatchFallback(after: QwenError.timeout))
        #expect(QwenError.allowsBatchFallback(after: QwenError.protocolError("closed")))
        #expect(QwenError.allowsBatchFallback(after: QwenError.server(status: 503, message: "busy")))
        #expect(!QwenError.allowsBatchFallback(after: QwenError.server(status: 401, message: "unauthorized")))
        #expect(!QwenError.allowsBatchFallback(after: QwenError.server(status: 403, message: "forbidden")))
        #expect(!QwenError.allowsBatchFallback(after: QwenError.server(status: 400, message: "bad request")))
        #expect(!QwenError.allowsBatchFallback(after: QwenError.missingConfiguration))
        #expect(!QwenError.allowsBatchFallback(after: QwenError.noSpeech))
        #expect(!QwenError.allowsBatchFallback(after: CancellationError()))
    }

    @Test("live Qwen endpoints accept realtime dictation and direct agent audio")
    func liveEndpoints() async throws {
        guard ProcessInfo.processInfo.environment["SAYKUKU_LIVE_QWEN_TEST"] == "1" else { return }
        let key = try #require(try KeychainStore().string(for: "qwen.apiKey"))
        let audioPath = try #require(ProcessInfo.processInfo.environment["SAYKUKU_TEST_AUDIO"])
        let expectedTranscript = ProcessInfo.processInfo.environment["SAYKUKU_TEST_PHRASE"] ?? "苹果"
        let selectedText = ProcessInfo.processInfo.environment["SAYKUKU_TEST_SELECTED_TEXT"]
        let expectedOutput = ProcessInfo.processInfo.environment["SAYKUKU_TEST_EXPECTED_OUTPUT"]
        let configuration = QwenConfiguration(
            region: .beijing,
            workspaceID: "",
            realtimeModel: "qwen3.5-omni-flash-realtime",
            reasoningModel: "qwen3.8-omni-flash"
        )
        let wav = try Data(contentsOf: URL(fileURLWithPath: audioPath))
        let pcm = Data(wav.dropFirst(44))

        let realtime = QwenRealtimeClient()
        let manualSession = UUID()
        try await realtime.connect(
            session: manualSession,
            apiKey: key,
            configuration: configuration,
            autoStop: false,
            onSpeechStopped: {},
            onDelta: { _ in }
        )
        for start in stride(from: 0, to: pcm.count, by: 3_200) {
            let end = min(start + 3_200, pcm.count)
            try await realtime.append(Data(pcm[start..<end]), session: manualSession)
        }
        let dictation = try await realtime.commit(session: manualSession)
        await realtime.cancel(session: manualSession)
        #expect(dictation.contains(expectedTranscript))

        let autoStopSession = UUID()
        try await realtime.connect(
            session: autoStopSession,
            apiKey: key,
            configuration: configuration,
            autoStop: true,
            onSpeechStopped: {},
            onDelta: { _ in }
        )
        // A stale cancel for the finished session must leave the new one open.
        await realtime.cancel(session: manualSession)
        await realtime.cancel(session: autoStopSession)

        let response = try await QwenReasoningClient().respondToAudio(
            apiKey: key,
            configuration: configuration,
            wav: wav,
            context: selectedText.map {
                [ContextItem(kind: .selectedText, symbol: "text.quote", title: "Selected text", value: $0)]
            } ?? [],
            sessions: []
        )
        #expect(response.transcript?.contains(expectedTranscript) == true)
        if let expectedOutput {
            #expect(response.action == .writeText)
            #expect(response.output?.localizedCaseInsensitiveContains(expectedOutput) == true)
        }
    }
}
