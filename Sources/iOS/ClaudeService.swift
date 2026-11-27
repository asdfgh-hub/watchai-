import Foundation

struct ClaudeService: Sendable {
    struct APIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // router.cheap exposes an Anthropic-compatible Messages API.
    private let baseURL = URL(string: "https://router.cheap/v1")!
    private let anthropicVersion = "2023-06-01"

    func fetchModels(apiKey: String) async throws -> [ClaudeModel] {
        let url = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        // The model catalogue is OpenAI-compatible and accepts Bearer auth.
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data, operation: "загрузка списка моделей")

        struct Envelope: Decodable { let data: [ClaudeModel] }
        let allModels = try JSONDecoder().decode(Envelope.self, from: data).data
        // This app sends requests through the Anthropic Messages endpoint,
        // so expose Claude model IDs only (other providers use other protocols).
        let models = allModels.filter { $0.id.localizedCaseInsensitiveContains("claude") }
        guard !models.isEmpty else {
            throw APIError(message: "Ключ авторизован, но Router.cheap не вернул Claude-модели для этого аккаунта. Проверь каталог моделей и доступ ключа. Другие провайдеры требуют отдельного протокола API.")
        }
        return models.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    func ask(text: String, imageData: Data? = nil, model: String, apiKey: String, systemPrompt: String) async throws -> String {
        let url = baseURL.appendingPathComponent("messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        // router.cheap's Anthropic-compatible endpoint requires x-api-key.
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var content: [[String: Any]] = []
        if let imageData {
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": imageData.base64EncodedString()
                ]
            ])
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
        try validate(response, data: data, operation: "отправка запроса")

        struct Response: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let answer = decoded.content.filter { $0.type == "text" }.compactMap(\.text).joined(separator: "\n")
        guard !answer.isEmpty else {
            throw APIError(message: "router.cheap вернул успешный ответ без текстового содержимого. Проверь, поддерживает ли выбранная модель формат Messages API.")
        }
        return answer
    }

    private func validate(_ response: URLResponse, data: Data, operation: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "Не удалось получить HTTP-ответ от router.cheap.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let errorObject = object?["error"] as? [String: Any]
            let errorType = errorObject?["type"] as? String ?? errorObject?["code"] as? String
            let rawMessage = errorObject?["message"] as? String
                ?? object?["message"] as? String
                ?? String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "Сервер не прислал описание ошибки"
            let serverMessage = String(rawMessage.prefix(900))
            let requestID = http.value(forHTTPHeaderField: "x-request-id")
                ?? http.value(forHTTPHeaderField: "request-id")
                ?? errorObject?["request_id"] as? String

            var guidance: String
            switch http.statusCode {
            case 401:
                guidance = "Проверь, что это действующий API-ключ именно от router.cheap, он вставлен полностью и без пробелов."
            case 402:
                guidance = "Похоже, на балансе router.cheap недостаточно средств для этого запроса. Проверь баланс."
            case 403:
                guidance = "router.cheap отклонил запрос. Проверь, разрешена ли выбранная модель для твоего ключа, нет ли ограничений аккаунта и правильно ли выбран протокол Messages API."
            case 404:
                guidance = "Модель не найдена или недоступна этому ключу. Обнови список моделей и выбери ID из полученного каталога."
            case 429:
                guidance = "Достигнут лимит запросов или провайдера. Попробуй позже либо выбери другую доступную модель."
            default:
                guidance = "Проверь каталог моделей, баланс и статус router.cheap."
            }

            var message = "router.cheap: ошибка HTTP \(http.statusCode) при операции «\(operation)». \(guidance)\nОтвет сервера: \(serverMessage)"
            if let errorType, !errorType.isEmpty { message += "\nТип ошибки: \(errorType)" }
            if let requestID, !requestID.isEmpty { message += "\nRequest ID: \(requestID)" }
            throw APIError(message: message)
        }
    }
}
