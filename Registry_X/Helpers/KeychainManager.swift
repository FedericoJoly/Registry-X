import Foundation
import Security

/// Manager for secure credential storage in Keychain
class KeychainManager {
    static let shared = KeychainManager()
    
    private let service = "com.newmagicstuff.registry-x"
    private let emailKey = "biometric_email"
    private let userIdKey = "biometric_userId"
    
    /// Save user credentials for biometric login
    func saveCredentials(email: String, userId: String) {
        save(key: emailKey, value: email)
        save(key: userIdKey, value: userId)
    }
    
    /// Load saved credentials
    func loadCredentials() -> (email: String, userId: String)? {
        guard let email = load(key: emailKey),
              let userId = load(key: userIdKey) else {
            return nil
        }
        return (email, userId)
    }
    
    /// Delete saved credentials
    func deleteCredentials() {
        delete(key: emailKey)
        delete(key: userIdKey)
    }
    
    /// Check if credentials are saved
    func hasCredentials() -> Bool {
        return loadCredentials() != nil
    }
    
    // MARK: - Private Helpers
    
    private func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        // Delete existing item first
        delete(key: key)
        
        // Add new item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return string
    }
    
    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
