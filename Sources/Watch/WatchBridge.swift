import Foundation
import WatchConnectivity
import Combine

@MainActor
final class WatchBridge: NSObject, ObservableObject {
    static let shared = WatchBridge()
    @Published var isLoading = false
    @Published var answer: String?
    @Published var error: String?
    @Published var status = "Готов к работе"
    @Published var lastRequest: WatchRequest?
    private var currentRequestID: String?

    func activate() {
        guard WCSession.isSupported() else { status = "Связь недоступна"; return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendPhotoRequest() {
        send(WatchRequest(id: UUID().uuidString, kind: "photos", text: nil))
    }

    func sendVoiceRequest(_ text: String) {
        send(WatchRequest(id: UUID().uuidString, kind: "voice", text: text))
    }

    private func send(_ request: WatchRequest) {
        answer = nil
        error = nil
        lastRequest = request
        currentRequestID = request.id
        isLoading = true
        status = "Отправляем запрос…"
        guard let data = try? JSONEncoder().encode(request) else {
            isLoading = false; error = "Не удалось подготовить запрос"; return
        }
        let payload: [String: Any] = ["request": data]
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { [weak self] response in
                Task { @MainActor in
                    if (response["accepted"] as? Bool) == true { self?.status = "Запрос принят iPhone" }
                }
            }, errorHandler: { [weak self] _ in
                session.transferUserInfo(payload)
                Task { @MainActor in self?.status = "Запрос поставлен в очередь" }
            })
        } else {
            session.transferUserInfo(payload)
            status = "Запрос поставлен в очередь до связи с iPhone"
        }
    }

    func cancelRequest() {
        guard let id = currentRequestID else { return }
        let session = WCSession.default
        let payload: [String: Any] = ["cancel": id]
        if session.isReachable { session.sendMessage(payload, replyHandler: nil, errorHandler: { _ in session.transferUserInfo(payload) }) }
        else { session.transferUserInfo(payload) }
        isLoading = false
        status = "Отмена отправлена"
        currentRequestID = nil
    }

    func reset() {
        answer = nil
        error = nil
        isLoading = false
        status = "Готов к работе"
        currentRequestID = nil
    }

    func showLocalError(_ message: String) {
        answer = nil
        isLoading = false
        error = message
        status = "Ошибка"
    }

    private func receive(_ message: [String: Any]) {
        guard let id = message["requestID"] as? String, id == currentRequestID,
              let text = message["text"] as? String else { return }
        isLoading = false
        currentRequestID = nil
        if let kind = message["result"] as? String, kind == "error" {
            error = text
            answer = nil
            status = "Ошибка"
        } else {
            answer = text
            status = "Ответ получен"
        }
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.status = error?.localizedDescription ?? (state == .activated ? "Связь с iPhone готова" : "Подключение…") }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        Task { @MainActor in self.receive(message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        Task { @MainActor in self.receive(userInfo) }
    }
}
