import Foundation
import Combine
import Security

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard
    @Published var modelID: String { didSet { defaults.set(modelID, forKey: "modelID") } }
    @Published var prompt: String { didSet { defaults.set(prompt, forKey: "prompt") } }
    @Published var photoCount: Int { didSet { defaults.set(photoCount, forKey: "photoCount") } }
    @Published var models: [ClaudeModel] {
        didSet {
            if let data = try? JSONEncoder().encode(models) {
                defaults.set(data, forKey: "cachedModels")
            }
        }
    }
    @Published var isLoadingModels = false
    @Published var modelError: String?

    private init() {
        modelID = defaults.string(forKey: "modelID") ?? "claude-sonnet-4-5"
        prompt = defaults.string(forKey: "prompt") ?? "Проанализируй материал внимательно. Отвечай на русском языке. Если это задание, реши его и объясни ход решения."
        photoCount = defaults.object(forKey: "photoCount") as? Int ?? 5
        if let data = defaults.data(forKey: "cachedModels"),
           let cached = try? JSONDecoder().decode([ClaudeModel].self, from: data) {
            models = cached
        } else {
            models = []
        }
    }

    var apiKey: String {
        get { KeychainStore.read() ?? "" }
        set { KeychainStore.save(newValue) }
    }
}

enum KeychainStore {
    private static let service = "com.wristai.app"
    private static let account = "anthropic-api-key"

    static func save(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
