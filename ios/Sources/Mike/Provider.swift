import Foundation
import Security

/// Where Mike's thinking happens. The choice is stored in UserDefaults (not a
/// secret); all keys and tokens live in the iPhone Keychain only.
enum InferenceProvider: String, Codable, CaseIterable, Identifiable {
    case local, groq, backend
    var id: String { rawValue }
    var title: String {
        switch self {
        case .local: return "On this iPhone"
        case .groq: return "Groq API"
        case .backend: return "Your own backend"
        }
    }
}

enum KeychainStore {
    static let service = "app.mike.ios"
    static let groqKey = "groq-api-key"
    static let backendToken = "backend-token"

    static func save(_ value: String, account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = Data(value.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func load(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }

    /// Earlier builds stored the backend token in UserDefaults. Move it to the
    /// Keychain once and remove the plaintext copy. Runs on every launch; cheap.
    static func migrateLegacyToken() {
        if let legacy = UserDefaults.standard.string(forKey: "mike.token"), !legacy.isEmpty {
            if load(backendToken) == nil { save(legacy, account: backendToken) }
            UserDefaults.standard.removeObject(forKey: "mike.token")
        }
    }
}

final class ProviderStore: ObservableObject {
    @Published var provider: InferenceProvider? {
        didSet { UserDefaults.standard.set(provider?.rawValue, forKey: "mike.provider") }
    }

    init() {
        KeychainStore.migrateLegacyToken()
        #if SIM_FORCE_LOCAL
        provider = .local
        #elseif SIM_FORCE_GROQ
        provider = .groq
        #else
        if let s = UserDefaults.standard.string(forKey: "mike.provider") {
            provider = InferenceProvider(rawValue: s)
        }
        #endif
    }

    var hasCompletedSetup: Bool { provider != nil }

    func select(_ p: InferenceProvider) { provider = p }
}
