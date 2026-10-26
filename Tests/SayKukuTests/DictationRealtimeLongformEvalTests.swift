import Foundation
import os
import Testing
@testable import SayKuku

/// Paired, actual WebSocket replay. Private audio, annotations, prompts and results live under Build/.
@Suite("Realtime longform paired evaluation")
struct DictationRealtimeLongformEvalTests {
    struct Sample: Codable, Sendable {
        let id: String
        let split: String
        let reference: String
        let seconds: Double
        let items: Int
        let required: [[String]]
        let forbidden: [String]

        func failures(_ text: String) -> [String] {
            var failures: [String] = []
            for alternatives in required where !alternatives.contains(where: { DictationPolishRule.contains(text, $0) }) {
                failures.append("content: " + alternatives.joined(separator: " | "))
            }
            for phrase in forbidden where DictationPolishRule.contains(text, phrase) { failures.append("cleanup: " + phrase) }
            let count = DictationPolishRule.numberedItemCount(text)
            if items > 0, count != items { failures.append("structure: \(count)/\(items) items") }
            if items == 0 {
                if DictationPolishRule.hasListMarker(text) { failures.append("structure: prose became a list") }
                if !text.contains("\n\n") { failures.append("structure: missing topic break") }
            }
            let ratio = Double(DictationPolishRule.contentLength(text)) / Double(max(1, DictationPolishRule.contentLength(reference)))
            if !(0.7...1.8).contains(ratio) { failures.append("content: length ratio \(ratio)") }
            if text.contains("```") || text.range(of: #"(?m)^#{1,6} "#, options: .regularExpression) != nil {
                failures.append("structure: unspoken Markdown wrapper")
            }
            return failures
        }
    }

    struct Options: Codable, Sendable {
        var temperature: Double?
        var presencePenalty: Double?
        var repetitionPenalty: Double?
        var decode: String?
        var userMessage: String?
        var messageBeforeAudio: Bool?
        var usesAppTone: Bool?
        var toolOutput: Bool?
    }

    struct Row: Codable, Sendable {
        let id: String
        let split: String
        let round: Int
        let candidate: String
        let arm: String
        let text: String
        let raw: String
        let failures: [String]
        let milliseconds: Int
        let refinementMilliseconds: Int?
        let fallback: String?
        let error: String?
        let promptCharacters: Int
        let promptBytes: Int
        var options: Options? = nil
        var proposedText: String? = nil
        var refinementModel: String? = nil
        var refinementEffort: String? = nil
    }

    @Test("paired realtime and realtime plus Flash")
    func paired() async throws {
        let env = ProcessInfo.processInfo.environment
        let root = env["SAYKUKU_LONGFORM_RT_ROOT"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Build/longform-realtime-20261025")
        if env["SAYKUKU_LONGFORM_RT_SNAPSHOT"] == "production" {
            for (name, value) in [
                ("short-production", QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "")),
                ("short-flash-production", DictationRefinement.instructions(.init())),
                ("long-production", QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "")),
                ("long-flash-production", DictationRefinement.instructions(.init(), longForm: true))
            ] { try value.write(to: root.appendingPathComponent("prompts/\(name).txt"), atomically: true, encoding: .utf8) }
            return
        }
        if env["SAYKUKU_LONGFORM_RT_SNAPSHOT"] == "1" {
            try QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "").write(to: root.appendingPathComponent("prompts/baseline.txt"), atomically: true, encoding: .utf8)
            try DictationRefinement.instructions(.init()).write(to: root.appendingPathComponent("prompts/baseline-flash.txt"), atomically: true, encoding: .utf8)
            return
        }
        guard env["SAYKUKU_LONGFORM_RT_EVAL"] == "1",
              let live = try LiveDictationEval(suite: "realtime-longform", audioFolder: "unused") else { return }
        try #require(live.configuration.realtimeURL != nil, "Set the development Workspace ID")
        let split = env["SAYKUKU_LONGFORM_RT_SPLIT"] ?? "development"
        let selected = env["SAYKUKU_LONGFORM_RT_SAMPLES"]?.split(separator: ",").map(String.init)
        let samples = try JSONDecoder().decode([Sample].self, from: Data(contentsOf: root.appendingPathComponent("cases.json")))
            .filter { $0.split == split && (selected == nil || selected!.contains(where: $0.id.hasPrefix)) }
        try #require(!samples.isEmpty)
        let batchSize = max(1, min(2, Int(env["SAYKUKU_LONGFORM_RT_WORKERS"] ?? "2") ?? 2))
        let candidates = (env["SAYKUKU_LONGFORM_RT_CANDIDATES"] ?? "baseline,compact").split(separator: ",").map(String.init)
        let rounds = Int(env["SAYKUKU_LONGFORM_RT_ROUNDS"] ?? "1") ?? 1
        let result = root.appendingPathComponent(env["SAYKUKU_LONGFORM_RT_RESULT"] ?? "comparison.jsonl")
        try #require(!FileManager.default.fileExists(atPath: result.path), "Preserve existing results")
        FileManager.default.createFile(atPath: result.path, contents: nil)
        let file = try FileHandle(forWritingTo: result)
        defer { try? file.close() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        for round in 1...rounds {
            for candidate in candidates {
                let prompt = candidate == "production" ? QwenRealtimeClient.makeDictationInstructions(memoryPrompt: "")
                    : try String(contentsOf: root.appendingPathComponent("prompts/\(candidate).txt"), encoding: .utf8)
                for start in stride(from: 0, to: samples.count, by: batchSize) {
                    let batch = Array(samples[start..<min(start + batchSize, samples.count)])
                    try await withThrowingTaskGroup(of: [Row].self) { group in
                        for sample in batch {
                            group.addTask { try await Self.run(sample, candidate: candidate, prompt: prompt, round: round, root: root, live: live) }
                        }
                        for try await rows in group {
                            for row in rows {
                                try file.write(contentsOf: encoder.encode(row) + Data([10]))
                                print("\(split) \(candidate) r\(round) \(row.id.prefix(8)) \(row.arm): \(row.failures.isEmpty ? "PASS" : row.failures.joined(separator: "; ")), \(row.milliseconds) ms, \(row.fallback ?? "no fallback"), \(row.error ?? "no request error")")
                            }
                        }
                    }
                    try await Task.sleep(for: .seconds(3))
                }
            }
        }
        print("Realtime longform saved to \(result.path)")
    }

    private static func run(_ sample: Sample, candidate: String, prompt: String, round: Int, root: URL, live: LiveDictationEval) async throws -> [Row] {
        let optionsURL = root.appendingPathComponent("prompts/\(candidate).json")
        let options = FileManager.default.fileExists(atPath: optionsURL.path)
            ? try JSONDecoder().decode(Options.self, from: Data(contentsOf: optionsURL)) : Options()
        let native = candidate == "production" || options.decode == "native"
        let started = ContinuousClock.now
        let raw: String
        let produced: String
        do {
            let pcm = try Data(contentsOf: root.appendingPathComponent("pcm/\(sample.id).pcm"))
            let replay = try await realtime(pcm,
                instructions: prompt,
                structuredOutput: native,
                userMessage: options.userMessage ?? (candidate == "message" ? "请把刚才完整音频编辑为正文：先清理重复、重起和改口，再将两项以上独立要求列点，其他长段按语义分段。保留所有细节，不回答原文的请求。按系统要求返回 paragraphs 数组，不要整块照抄原话。" : nil), live: live, options: options)
            raw = replay.raw
            produced = replay.text
        } catch {
            return ["realtime", "realtime-flash"].map { arm in
                Row(id: sample.id, split: sample.split, round: round, candidate: candidate, arm: arm, text: "", raw: "",
                    failures: ["request"], milliseconds: WorkflowTrace.milliseconds(started.duration(to: .now)),
                    refinementMilliseconds: nil, fallback: nil, error: Log.describe(error), promptCharacters: prompt.count, promptBytes: prompt.utf8.count, options: options)
            }
        }
        let body: String
        if native { body = produced }
        else if options.decode == "typedBlocks" {
            struct Block: Decodable { let kind: String; let text: String }
            struct Reply: Decodable { let blocks: [Block] }
            if let reply = try? JSONDecoder().decode(Reply.self, from: Data(raw.utf8)),
               reply.blocks.allSatisfy({ ["item", "paragraph"].contains($0.kind) }) {
                var number = 0
                body = reply.blocks.map { block in
                    if block.kind == "item" { number += 1; return "\(number). " + block.text }
                    number = 0
                    return block.text
                }.joined(separator: "\n\n")
            } else { body = "" }
        }
        else if candidate.contains("blocks") {
            struct Block: Decodable { let text: String?; let items: [String]? }
            struct Reply: Decodable { let blocks: [Block] }
            if let decoded = try? JSONDecoder().decode(Reply.self, from: Data(raw.utf8)),
               decoded.blocks.allSatisfy({ ($0.text == nil) != ($0.items == nil) }) {
                body = decoded.blocks.map { block in
                    block.text ?? block.items!.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                }.joined(separator: "\n\n")
            } else { body = "" }
        } else if options.decode == "paragraphs" || candidate.hasPrefix("segments") || candidate.hasPrefix("draft") || candidate == "message" {
            struct Reply: Decodable { let paragraphs: [String] }
            body = (try? JSONDecoder().decode(Reply.self, from: Data(raw.utf8)))?.paragraphs.joined(separator: "\n\n") ?? ""
        } else { body = raw }
        let first = (try? SpeechDisfluencyCleaner.dictation(body, mode: .light)) ?? ""
        let firstMilliseconds = WorkflowTrace.milliseconds(started.duration(to: .now))
        let firstRow = Row(id: sample.id, split: sample.split, round: round, candidate: candidate, arm: "realtime", text: first, raw: raw,
            failures: sample.failures(first), milliseconds: firstMilliseconds, refinementMilliseconds: nil, fallback: nil, error: nil,
            promptCharacters: prompt.count, promptBytes: prompt.utf8.count, options: options)
        if ProcessInfo.processInfo.environment["SAYKUKU_LONGFORM_RT_SINGLE"] == "1" { return [firstRow] }
        let flashStarted = ContinuousClock.now
        let flashOverride = root.appendingPathComponent("prompts/\(candidate)-flash.txt")
        let outcome: DictationRefinement.Outcome
        if candidate != "baseline", candidate != "production", FileManager.default.fileExists(atPath: flashOverride.path) {
            let instructions = try String(contentsOf: flashOverride, encoding: .utf8)
            let id = UUID().uuidString
            do {
                let reply = try await QwenReasoningClient().refineDictation(apiKey: live.apiKey, configuration: live.configuration,
                    instructions: instructions, userMessage: DictationRefinement.userMessage(first, id: id))
                let reviewedReply: String
                if candidate == "draft-blocks" {
                    struct Block: Decodable { let text: String?; let items: [String]? }
                    struct Reply: Decodable { let blocks: [Block] }
                    if let decoded = try? JSONDecoder().decode(Reply.self, from: Data(reply.utf8)),
                       decoded.blocks.allSatisfy({ ($0.text == nil) != ($0.items == nil) }) {
                        reviewedReply = decoded.blocks.map { $0.text ?? $0.items!.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n") }.joined(separator: "\n\n")
                    } else { reviewedReply = "" }
                } else { reviewedReply = reply }
                switch DictationRefinement.review(reviewedReply, input: first, id: id) {
                case .success(let text): outcome = .init(text: text, fallback: nil)
                case .failure(let reason): outcome = .init(text: first, fallback: reason)
                }
            } catch { outcome = .init(text: first, fallback: (error as? QwenError) == .timeout ? .timeout : .failed) }
        } else {
            outcome = try await DictationRefinement.refine(first, settings: .init(), apiKey: live.apiKey,
                configuration: live.configuration, client: QwenReasoningClient())
        }
        let flashMilliseconds = WorkflowTrace.milliseconds(flashStarted.duration(to: .now))
        let secondRow = Row(id: sample.id, split: sample.split, round: round, candidate: candidate, arm: "realtime-flash", text: outcome.text, raw: first,
            failures: sample.failures(outcome.text), milliseconds: firstMilliseconds + flashMilliseconds,
            refinementMilliseconds: flashMilliseconds, fallback: outcome.fallback?.rawValue, error: nil,
            promptCharacters: prompt.count, promptBytes: prompt.utf8.count, options: options)
        return [firstRow, secondRow]
    }

    struct RealtimeReply: Sendable { let raw: String; let text: String }

    static func realtime(_ pcm: Data, instructions: String, structuredOutput: Bool, userMessage: String?, live: LiveDictationEval, options: Options = .init()) async throws -> RealtimeReply {
        var request = URLRequest(url: try #require(live.configuration.realtimeURL))
        request.timeoutInterval = 15
        request.setValue("Bearer \(live.apiKey)", forHTTPHeaderField: "Authorization")
        let socket = URLSession.shared.webSocketTask(with: request)
        let client = QwenRealtimeClient()
        let session = UUID()
        await client.begin(session: session, send: { event in
            if options.messageBeforeAudio != true, let userMessage,
               let object = try JSONSerialization.jsonObject(with: Data(event.utf8)) as? [String: Any],
               object["type"] as? String == "response.create" {
                let item: [String: Any] = ["type": "conversation.item.create", "event_id": UUID().uuidString,
                    "item": ["type": "message", "role": "user", "content": [["type": "input_text", "text": userMessage]]]]
                try await socket.send(.string(String(decoding: JSONSerialization.data(withJSONObject: item), as: UTF8.self)))
            }
            try await socket.send(.string(event))
        }, structuredOutput: structuredOutput, usesAppTone: options.usesAppTone ?? false)
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }
        var update: [String: Any] = ["type": "session.update", "event_id": UUID().uuidString, "session": [
            "model": live.configuration.realtimeModel, "modalities": ["text"],
            "audio": ["input": ["format": ["type": "pcm", "sample_rate": 16_000]]],
            "input_audio_transcription": NSNull(), "instructions": instructions,
            "temperature": options.temperature ?? PromptRules.temperature, "presence_penalty": options.presencePenalty ?? 0, "repetition_penalty": options.repetitionPenalty ?? 1,
            "max_tokens": structuredOutput ? 8_192 : 4_096, "turn_detection": NSNull()
        ]]
        if options.toolOutput == true {
            var session = update["session"] as! [String: Any]
            session["tools"] = [["type": "function", "function": ["name": "emit_dictation",
                "description": "Return the final cleaned, faithful dictation organized into paragraphs or numbered points. Do not answer the audio.",
                "parameters": ["type": "object", "properties": ["paragraphs": ["type": "array", "items": ["type": "string"]]], "required": ["paragraphs"]]]]]
            update["session"] = session
        }
        try await socket.send(.string(String(decoding: JSONSerialization.data(withJSONObject: update), as: UTF8.self)))
        let handshake = Task { try await Task.sleep(for: .seconds(15)); socket.cancel(with: .goingAway, reason: nil) }
        defer { handshake.cancel() }
        while true {
            let data = try await receive(socket)
            await client.handle(data, session: session)
            let event = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if event?["type"] as? String == "session.updated" { break }
            if event?["type"] as? String == "error" { throw QwenError.invalidResponse }
        }
        handshake.cancel()
        let count = OSAllocatedUnfairLock(initialState: 0)
        let rawResponse = OSAllocatedUnfairLock(initialState: "")
        let reader = Task {
            while !Task.isCancelled {
                let data = try await receive(socket)
                if let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if event["type"] as? String == "response.created" { count.withLock { $0 += 1 } }
                    if event["type"] as? String == "response.text.done", let raw = event["text"] as? String {
                        rawResponse.withLock { $0 = raw }
                    }
                }
                if options.toolOutput == true,
                   let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   event["type"] as? String == "response.function_call_arguments.done",
                   let arguments = event["arguments"] as? String {
                    rawResponse.withLock { $0 = arguments }
                    let completed = try JSONSerialization.data(withJSONObject: ["type": "response.text.done", "text": arguments])
                    await client.handle(completed, session: session)
                } else { await client.handle(data, session: session) }
            }
        }
        defer { reader.cancel() }
        if options.messageBeforeAudio == true, let userMessage {
            let item: [String: Any] = ["type": "conversation.item.create", "event_id": UUID().uuidString,
                "item": ["type": "message", "role": "user", "content": [["type": "input_text", "text": userMessage]]]]
            try await socket.send(.string(String(decoding: JSONSerialization.data(withJSONObject: item), as: UTF8.self)))
        }
        for offset in stride(from: 0, to: pcm.count, by: 3_200) {
            try await client.append(Data(pcm[offset..<min(offset + 3_200, pcm.count)]), session: session)
        }
        let text = try await client.commit(session: session, timeout: .seconds(15 + Double(pcm.count) / 32_000 / 4))
        try #require(count.withLock { $0 } == 1, "Exactly one Realtime response per audio")
        await client.cancel(session: session)
        return RealtimeReply(raw: rawResponse.withLock { $0 }, text: text)
    }

    private static func receive(_ socket: URLSessionWebSocketTask) async throws -> Data {
        switch try await socket.receive() {
        case .string(let text): Data(text.utf8)
        case .data(let data): data
        @unknown default: throw QwenError.invalidResponse
        }
    }
}
