import Foundation

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
