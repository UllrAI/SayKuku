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

    @Test("realtime dictation never settles for a partial transcript")
    func partialTranscriptTimesOut() async throws {
        let client = QwenRealtimeClient()
        let session = UUID()
        await client.begin(session: session, send: { _ in })
        try await client.handle(serverEvent(["type": "response.text.delta", "delta": "明天下午"]), session: session)
        await #expect(throws: QwenError.timeout) {
            try await client.commit(session: session, timeout: .milliseconds(50))
        }
    }

    @Test("realtime dictation returns the done text, not the deltas before it")
    func transcriptWaitsForDone() async throws {
        let client = QwenRealtimeClient()
        let sent = SentEvents()
        let session = UUID()
        await client.begin(session: session, send: { await sent.record($0) })
        try await client.handle(serverEvent(["type": "response.text.delta", "delta": "明天下午"]), session: session)
        async let transcript = client.commit(session: session, timeout: .seconds(5))
        // Let commit send its events and start waiting before the response finishes.
        while await sent.types != ["input_audio_buffer.commit", "response.create"] { await Task.yield() }
        try await client.handle(serverEvent(["type": "response.text.done", "text": "明天下午开会。"]), session: session)
        #expect(try await transcript == "明天下午开会。")
    }

    @Test("stopping by hand commits the audio unless server VAD already did")
    func commitSentUnlessServerCommitted() async throws {
        let client = QwenRealtimeClient()
        let sent = SentEvents()
        let handStopped = UUID()
        await client.begin(session: handStopped, send: { await sent.record($0) })
        try await client.handle(serverEvent(["type": "response.text.done", "text": "好的"]), session: handStopped)
        #expect(try await client.commit(session: handStopped, timeout: .seconds(5)) == "好的")
        #expect(await sent.types == ["input_audio_buffer.commit", "response.create"])

        let vadStopped = UUID()
        await client.begin(session: vadStopped, send: { await sent.record($0) })
        try await client.handle(serverEvent(["type": "input_audio_buffer.speech_stopped"]), session: vadStopped)
        try await client.handle(serverEvent(["type": "response.text.done", "text": "好的"]), session: vadStopped)
        #expect(try await client.commit(session: vadStopped, timeout: .seconds(5)) == "好的")
        #expect(await sent.types.count == 2)
    }

    @Test("a realtime error that arrives early surfaces on the next send and wait")
    func earlyErrorIsKept() async throws {
        let client = QwenRealtimeClient()
        let sent = SentEvents()
        let session = UUID()
        let rateLimited = QwenError.protocolError("Requests rate limit exceeded")
        await client.begin(session: session, send: { await sent.record($0) })
        try await client.handle(serverEvent(["type": "input_audio_buffer.speech_stopped"]), session: session)
        try await client.handle(
            serverEvent(["type": "error", "error": ["message": "Requests rate limit exceeded"]]),
            session: session
        )
        await #expect(throws: rateLimited) {
            try await client.append(Data([0, 1]), session: session)
        }
        await #expect(throws: rateLimited) {
            try await client.commit(session: session, timeout: .seconds(5))
        }
        #expect(await sent.types.isEmpty)
    }

    @Test("frames that are not JSON events are skipped")
    func nonJSONFramesSkipped() async throws {
        let client = QwenRealtimeClient()
        let session = UUID()
        await client.begin(session: session, send: { _ in })
        await client.handle(Data("pong".utf8), session: session)
        await client.handle(Data([0xFF, 0x00]), session: session)
        try await client.handle(serverEvent(["type": "response.text.done", "text": "你好"]), session: session)
        #expect(try await client.commit(session: session, timeout: .seconds(5)) == "你好")
    }

    @Test("live Qwen endpoints accept realtime dictation and direct agent audio")
    func liveEndpoints() async throws {
        guard ProcessInfo.processInfo.environment["SAYKUKU_LIVE_QWEN_TEST"] == "1" else { return }
        let key = try #require(try KeychainStore().string(for: "qwen.apiKey"))
        let audioPath = try #require(ProcessInfo.processInfo.environment["SAYKUKU_TEST_AUDIO"])
        let expectedTranscript = ProcessInfo.processInfo.environment["SAYKUKU_TEST_PHRASE"] ?? "苹果"
        let selectedText = ProcessInfo.processInfo.environment["SAYKUKU_TEST_SELECTED_TEXT"]
        let expectedOutput = ProcessInfo.processInfo.environment["SAYKUKU_TEST_EXPECTED_OUTPUT"]
        // Realtime is only served on workspace hosts, so the live test needs a workspace ID.
        let workspaceID = try #require(ProcessInfo.processInfo.environment["SAYKUKU_TEST_WORKSPACE_ID"])
        let region = ProcessInfo.processInfo.environment["SAYKUKU_TEST_REGION"].flatMap(QwenRegion.init(rawValue:)) ?? .beijing
        let configuration = QwenConfiguration(
            region: region,
            workspaceID: workspaceID,
            realtimeModel: QwenModelCatalog.defaultRealtimeModel,
            reasoningModel: QwenModelCatalog.defaultReasoningModel
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
        let dictation = try await realtime.commit(session: manualSession, timeout: .seconds(15))
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

private func serverEvent(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
}

/// Types of the client events a realtime session sent, in order.
private actor SentEvents {
    private(set) var types: [String] = []

    func record(_ event: String) {
        let object = try? JSONSerialization.jsonObject(with: Data(event.utf8)) as? [String: Any]
        types.append(object?["type"] as? String ?? "")
    }
}
