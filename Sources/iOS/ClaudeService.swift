import Foundation

struct ClaudeService: Sendable {
    struct APIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let base = URL(string: "https://api.anthropic.com")!
    private let apiVersion = "2026-10-21"

    func fetchModels(apiKey: String, workspaceID: String? = nil) async throws -> [ClaudeModel] {
        var components = URLComponents(url: base.appendingPathComponent("v1/models"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: "100")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let workspaceID = workspaceID?.trimmingCharacters(in: .whitespacesAndNewlines), !workspaceID.isEmpty {
            request.setValue(workspaceID, forHTTPHeaderField: "anthropic-workspace-id")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)

        struct Envelope: Decodable { let data: [ClaudeModel] }
        let models = try JSONDecoder().decode(Envelope.self, from: data).data
        guard !models.isEmpty else {
            throw APIError(message: "Anthropic API ответил успешно, но не вернул ни одной доступной модели. Проверь доступ Workspace к моделям в Claude Console.")
        }
        return models.sorted { $0.id < $1.id }
    }

    func ask(text: String, imageData: Data? = nil, model: String, apiKey: String, workspaceID: String? = nil, systemPrompt: String) async throws -> String {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw APIError(message: "Неверный адрес API")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let workspaceID = workspaceID?.trimmingCharacters(in: .whitespacesAndNewlines), !workspaceID.isEmpty {
            request.setValue(workspaceID, forHTTPHeaderField: "anthropic-workspace-id")
        }

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
        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "Нет ответа от сервера")
        }
        guard (200..<300).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = object?["error"] as? [String: Any]
            let errorType = error?["type"] as? String ?? ""
            let rawServerMessage = error?["message"] as? String
                ?? String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "Сервер не прислал описание ошибки"
            let serverMessage = String(rawServerMessage.prefix(600))
            let requestID = http.value(forHTTPHeaderField: "request-id")
                ?? http.value(forHTTPHeaderField: "anthropic-request-id")

            var message: String
            if http.statusCode == 403 && errorType == "permission_error" {
                message = "Anthropic вернул 403 permission_error: у API-ключа нет прав на этот ресурс. Проверь в Claude Console права организации и Workspace. Если ключ не привязан к одному Workspace, укажи его ID в настройках WristAI. Также проверь, что это ключ из Claude Console, а не подписка Claude.ai."
            } else if http.statusCode == 403 {
                message = "Получен HTTP 403 Request not allowed. Запрос отклонён. Если ответ сервера — HTML/Cloudflare, вероятна блокировка на уровне сети или IP. Если ответ JSON — проверь права ключа, Workspace и доступность региона в Claude Console/документации Anthropic."
            } else {
                message = "Claude API (\(http.statusCode)): \(serverMessage)"
            }

            if http.statusCode == 403 {
                message += "\nОтвет сервера: \(serverMessage)"
            }
            if !errorType.isEmpty { message += "\nТип ошибки: \(errorType)" }
            if let requestID { message += "\nRequest ID: \(requestID)" }
            throw APIError(message: message)
        }
    }
}
