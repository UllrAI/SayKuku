import Foundation
import Testing
@testable import SayKuku

@Suite("Text write diagnostic timing")
@MainActor
struct TextWriteTraceTests {
    @Test("repeated reads accumulate before rounding without changing their enclosing duration")
    func accumulatedReads() {
        let trace = TextWriteTrace(bundleID: "com.saykuku.tests")
        trace.record(.pasteVerify, duration: .milliseconds(501))
        trace.record(.pasteVerifyReads, duration: .microseconds(400))
        trace.record(.pasteVerifyReads, duration: .microseconds(400))
        #expect(trace.milliseconds(.pasteVerifyReads) == 1)
        #expect(trace.milliseconds(.pasteVerify) == 501)
        #expect(trace.milliseconds(.axVerify) == nil)
    }

    @Test("measurement executes once, preserves values and propagates errors and cancellation")
    func transparentMeasurement() async throws {
        enum Failure: Error { case expected }
        let trace = TextWriteTrace(bundleID: "com.saykuku.tests")
        var calls = 0
        let value = trace.measure(.clipboardBackup) { calls += 1; return 42 }
        #expect(value == 42 && calls == 1)
        #expect(trace.milliseconds(.clipboardBackup) != nil)
        #expect(throws: Failure.self) {
            try trace.measure(.pasteValidate) { calls += 1; throw Failure.expected }
        }
        #expect(calls == 2 && trace.milliseconds(.pasteValidate) != nil)
        do {
            let _: Int = try await trace.measure(.pasteDelay) {
                calls += 1
                await Task.yield()
                throw CancellationError()
            }
            Issue.record("Cancellation must propagate")
        } catch is CancellationError {
            #expect(calls == 3 && trace.milliseconds(.pasteDelay) != nil)
        }
    }
}
