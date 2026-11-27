import Foundation
import Combine

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    @Published private(set) var chats: [ChatRecord] = []
    private let url: URL

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = dir.appendingPathComponent("wristai-history.json")
        load()
    }

    func add(_ chat: ChatRecord) {
        chats.insert(chat, at: 0)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ChatRecord].self, from: data) else { return }
        chats = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(chats) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
