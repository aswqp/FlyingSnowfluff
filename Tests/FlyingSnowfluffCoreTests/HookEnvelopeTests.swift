import Foundation
import Testing
@testable import FlyingSnowfluffCore

@Suite("Hook envelope")
struct HookEnvelopeTests {
    @Test func promptPayloadKeepsIdentifiersButDropsPromptText() throws {
        let input = Data(#"{"session_id":"s-1","turn_id":"t-9","prompt":"extremely private"}"#.utf8)
        let envelope = try #require(HookEnvelopeParser.parse(
            input,
            forcedEvent: .userPromptSubmit,
            timestamp: Date(timeIntervalSince1970: 123)
        ))

        #expect(envelope.event == .working)
        #expect(envelope.sessionID == "s-1")
        #expect(envelope.turnID == "t-9")
        #expect(!String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self).contains("private"))
    }

    @Test func postToolErrorMapsToFailed() throws {
        let input = Data(#"{"session_id":"s","tool_response":{"isError":true,"exit_code":1}}"#.utf8)
        let envelope = try #require(HookEnvelopeParser.parse(input, forcedEvent: .postToolUse))
        #expect(envelope.event == .failed)
    }

    @Test func successfulPostToolRestoresWorking() throws {
        let input = Data(#"{"session_id":"s","tool_response":{"isError":false,"exit_code":0}}"#.utf8)
        let envelope = try #require(HookEnvelopeParser.parse(input, forcedEvent: .postToolUse))
        #expect(envelope.event == .working)
    }

    @Test func invalidOrOversizedInputIsRejectedFailOpen() {
        #expect(HookEnvelopeParser.parse(Data("not json".utf8), forcedEvent: .preToolUse) == nil)
        #expect(HookEnvelopeParser.parse(Data(repeating: 65, count: 65_537), forcedEvent: .stop) == nil)
    }

    @Test func explicitMappingMatchesCodexContract() {
        #expect(HookEnvelopeParser.parse(Data("{}".utf8), forcedEvent: .preToolUse)?.event == .toolRunning)
        #expect(HookEnvelopeParser.parse(Data("{}".utf8), forcedEvent: .permissionRequest)?.event == .needsInput)
        #expect(HookEnvelopeParser.parse(Data("{}".utf8), forcedEvent: .stop)?.event == .ready)
        #expect(HookEnvelopeParser.parse(Data("{}".utf8), forcedEvent: .sessionEnd)?.event == .idle)
    }
}
