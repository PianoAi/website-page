import Foundation
import Security

enum Keychain {
    enum Key: String, CaseIterable {
        case accessToken  = "io.pianoai.access_token"
        case refreshToken = "io.pianoai.refresh_token"
        case sessionId    = "io.pianoai.session_id"
    }

    @discardableResult
    static func save(_ value: String, for key: Key) -> Bool {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key.rawValue,
            kSecValueData:   data
        ]
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func load(for key: Key) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key.rawValue,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(_ key: Key) -> Bool {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key.rawValue
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    static func clear() {
        Key.allCases.forEach { delete($0) }
    }
}
