import Foundation

public enum HookCommandEvent: String, Codable, CaseIterable, Sendable {
    case userPromptSubmit
    case preToolUse
    case permissionRequest
    case postToolUse
    case stop
    case sessionEnd
}

public struct HookEnvelope: Codable, Equatable, Sendable {
    public static let protocolVersion = 1

    public let version: Int
    public let event: PetActivity
    public let sessionID: String?
    public let turnID: String?
    public let timestamp: TimeInterval

    public init(event: PetActivity, sessionID: String?, turnID: String?, timestamp: Date) {
        version = Self.protocolVersion
        self.event = event
        self.sessionID = sessionID
        self.turnID = turnID
        self.timestamp = timestamp.timeIntervalSince1970
    }
}

public enum HookEnvelopeParser {
    public static let maximumInputBytes = 65_536

    public static func parse(
        _ data: Data,
        forcedEvent: HookCommandEvent,
        timestamp: Date = Date()
    ) -> HookEnvelope? {
        guard data.count <= maximumInputBytes,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { return nil }

        let event: PetActivity
        switch forcedEvent {
        case .userPromptSubmit: event = .working
        case .preToolUse: event = .toolRunning
        case .permissionRequest: event = .needsInput
        case .postToolUse: event = responseFailed(dictionary) ? .failed : .working
        case .stop: event = .ready
        case .sessionEnd: event = .idle
        }

        return HookEnvelope(
            event: event,
            sessionID: stringValue(in: dictionary, keys: ["session_id", "sessionId", "conversation_id"]),
            turnID: stringValue(in: dictionary, keys: ["turn_id", "turnId"]),
            timestamp: timestamp
        )
    }

    private static func stringValue(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return String(value.prefix(256))
            }
        }
        return nil
    }

    private static func responseFailed(_ object: [String: Any]) -> Bool {
        let candidate = (object["tool_response"] as? [String: Any])
            ?? (object["toolResponse"] as? [String: Any])
            ?? object
        if candidate["isError"] as? Bool == true || candidate["is_error"] as? Bool == true {
            return true
        }
        for key in ["exit_code", "exitCode", "status_code"] {
            if let code = candidate[key] as? Int, code != 0 { return true }
            if let number = candidate[key] as? NSNumber, number.intValue != 0 { return true }
        }
        if let status = candidate["status"] as? String {
            return ["failed", "failure", "error"].contains(status.lowercased())
        }
        return false
    }
}
