import Foundation

struct ClaudeService: Sendable {
    struct APIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let base = URL(string: "https://api.anthropic.com")!

    func fetchModels(apiKey: String) async throws -> [ClaudeModel] {
        var components = URLComponents(url: base.appendingPathComponent("v1/models"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: "100")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        struct Envelope: Decodable { let data: [ClaudeModel] }
        return try JSONDecoder().decode(Envelope.self, from: data).data.sorted { $0.id < $1.id }
    }

    func ask(text: String, imageData: Data? = nil, model: String, apiKey: String, systemPrompt: String) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { throw APIError(message: "Неверный адрес API") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var content: [[String: Any]] = []
        if let imageData {
            content.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": imageData.base64EncodedString()]])
        }
        content.append(["type": "text", "text": text])
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1800,
            "system": systemPrompt,
            "messages": [["role": "user", "content": content]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        struct Response: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let answer = decoded.content.filter { $0.type == "text" }.compactMap(\.text).joined(separator: "\n")
        guard !answer.isEmpty else { throw APIError(message: "Claude вернул пустой ответ") }
        return answer
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError(message: "Нет ответа от сервера") }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            let error = detail?["error"] as? [String: Any]
            let message = error?["message"] as? String ?? String(data: data, encoding: .utf8) ?? "Неизвестная ошибка"
            throw APIError(message: "Claude API (\(http.statusCode)): \(message)")
        }
    }
}
