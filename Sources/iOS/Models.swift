import Foundation

struct ClaudeModel: Identifiable, Codable, Hashable {
    let id: String
    var display_name: String?
    var name: String { display_name ?? id }
}

struct ChatMessage: Identifiable, Codable {
    enum Role: String, Codable { case user, assistant }
    var id = UUID()
    var role: Role
    var text: String
    var createdAt = Date()
}

struct ChatRecord: Identifiable, Codable {
    var id = UUID()
    var title: String
    var kind: String
    var createdAt = Date()
    var messages: [ChatMessage]
}

struct WatchRequest: Codable {
    var id: String
    var kind: String // "voice" or "photos"
    var text: String?
}

enum BridgePayload {
    static let request = "request"
    static let accepted = "accepted"
    static let result = "result"
    static let error = "error"
    static let text = "text"
    static let requestID = "requestID"
}
