import Foundation
import WatchConnectivity
import UIKit
import Photos
import Combine

@MainActor
final class PhoneWatchBridge: NSObject, ObservableObject {
    static let shared = PhoneWatchBridge()
    @Published var status = "Ожидание часов"
    @Published var lastError: String?
    private let service = ClaudeService()
    private let photos = PhotoLibraryService()
    private var activeBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var requestTasks: [String: Task<Void, Never>] = [:]

    func activate() {
        guard WCSession.isSupported() else { status = "WatchConnectivity недоступен"; return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func beginBackgroundTime() {
        guard activeBackgroundTask == .invalid else { return }
        activeBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "WristAI Claude request") { [weak self] in
            Task { @MainActor in self?.endBackgroundTime() }
        }
    }

    private func endBackgroundTime() {
        guard activeBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(activeBackgroundTask)
        activeBackgroundTask = .invalid
    }

    private func start(_ request: WatchRequest) {
        requestTasks[request.id]?.cancel()
        requestTasks[request.id] = Task { [weak self] in
            guard let self else { return }
            await self.handle(request)
            self.requestTasks.removeValue(forKey: request.id)
        }
    }

    private func cancel(_ id: String) {
        requestTasks[id]?.cancel()
        requestTasks.removeValue(forKey: id)
        sendToWatch(BridgePayload.error, requestID: id, text: "Запрос отменён")
    }

    private func sendToWatch(_ kind: String, requestID: String, text: String) {
        let payload: [String: Any] = [BridgePayload.result: kind, BridgePayload.requestID: requestID, BridgePayload.text: text]
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                session.transferUserInfo(payload)
                print("WristAI sendMessage failed: \(error.localizedDescription)")
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func handle(_ request: WatchRequest) async {
        beginBackgroundTime()
        defer { endBackgroundTime() }
        do {
            let settings = AppSettings.shared
            let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw ClaudeService.APIError(message: "Сначала добавь Claude API Key в настройках iPhone") }
            status = "Обрабатывается запрос с часов"
            lastError = nil
            let answer: String
            let title: String
            if request.kind == "voice" {
                let question = request.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !question.isEmpty else { throw ClaudeService.APIError(message: "Пустой голосовой запрос") }
                answer = try await service.ask(text: question, model: settings.modelID, apiKey: key, workspaceID: settings.workspaceID, systemPrompt: settings.prompt)
                title = String(question.prefix(70))
                HistoryStore.shared.add(ChatRecord(title: title, kind: "Голос", messages: [
                    ChatMessage(role: .user, text: question), ChatMessage(role: .assistant, text: answer)
                ]))
            } else {
                let images = try await photos.latestJPEGs(count: settings.photoCount)
                let claudeService = service
                let selectedModel = settings.modelID
                let sharedPrompt = settings.prompt
                let workspaceID = settings.workspaceID
                var results = Array(repeating: "", count: images.count)
                try await withThrowingTaskGroup(of: (Int, String).self) { group in
                    var next = 0
                    func add(_ index: Int) {
                        group.addTask {
                            let response = try await claudeService.ask(text: "Проанализируй эту фотографию отдельно. Это изображение \(index + 1) из \(images.count).", imageData: images[index], model: selectedModel, apiKey: key, workspaceID: workspaceID, systemPrompt: sharedPrompt)
                            return (index, response)
                        }
                    }
                    while next < min(2, images.count) { add(next); next += 1 }
                    while let (index, response) = try await group.next() {
                        results[index] = response
                        if next < images.count { add(next); next += 1 }
                    }
                }
                answer = results.enumerated().map { "ФОТО \($0.offset + 1)\n\n\($0.element)" }.joined(separator: "\n\n──────────\n\n")
                title = "Анализ \(images.count) фотографий"
                HistoryStore.shared.add(ChatRecord(title: title, kind: "Фото", messages: [
                    ChatMessage(role: .user, text: "Анализ последних \(images.count) фотографий из медиатеки"),
                    ChatMessage(role: .assistant, text: answer)
                ]))
            }
            status = "Последний запрос выполнен"
            sendToWatch(BridgePayload.result, requestID: request.id, text: answer)
        } catch {
            let message = error is CancellationError ? "Запрос отменён" : error.localizedDescription
            status = "Ошибка запроса"
            lastError = message
            sendToWatch(BridgePayload.error, requestID: request.id, text: message)
        }
    }
}

extension PhoneWatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.status = error?.localizedDescription ?? (state == .activated ? "Часы подключены" : "Подключение часов") }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        if let cancelID = message["cancel"] as? String {
            replyHandler([BridgePayload.accepted: true])
            Task { @MainActor in self.cancel(cancelID) }
            return
        }
        guard let raw = message[BridgePayload.request] as? Data,
              let request = try? JSONDecoder().decode(WatchRequest.self, from: raw) else {
            replyHandler([BridgePayload.accepted: false]); return
        }
        replyHandler([BridgePayload.accepted: true])
        Task { @MainActor in self.start(request) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        if let cancelID = userInfo["cancel"] as? String {
            Task { @MainActor in self.cancel(cancelID) }
            return
        }
        guard let raw = userInfo[BridgePayload.request] as? Data,
              let request = try? JSONDecoder().decode(WatchRequest.self, from: raw) else { return }
        Task { @MainActor in self.start(request) }
    }
}
