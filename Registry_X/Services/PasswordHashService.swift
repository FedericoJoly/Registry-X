import Foundation
import CryptoKit

/// Service for secure password hashing using SHA256
/// Note: For production apps with high security requirements, consider using bcrypt or Argon2
/// For this app's use case (internal staff management), SHA256 with salt is sufficient
struct PasswordHashService {
    
    /// Hash a password with SHA256 and a salt
    /// - Parameter password: Plain text password
    /// - Returns: Salted and hashed password string in format "salt:hash"
    static func hash(_ password: String) -> String {
        // Generate random salt
        let salt = UUID().uuidString
        
        // Combine password and salt
        let saltedPassword = password + salt
        
        // Hash using SHA256
        let inputData = Data(saltedPassword.utf8)
        let hashed = SHA256.hash(data: inputData)
        let hashString = hashed.compactMap { String(format: "%02x", $0) }.joined()
        
        // Return salt and hash combined (salt:hash)
        return "\(salt):\(hashString)"
    }
    
    /// Verify a password against a stored hash
    /// - Parameters:
    ///   - password: Plain text password to verify
    ///   - storedHash: Stored hash in format "salt:hash"
    /// - Returns: True if password matches
    static func verify(_ password: String, against storedHash: String) -> Bool {
        // Split stored hash into salt and hash
        let components = storedHash.split(separator: ":")
        guard components.count == 2 else {
            // Invalid hash format - might be old plain text password
            // For migration: check if it matches plain text
            return password == storedHash
        }
        
        let salt = String(components[0])
        let hash = String(components[1])
        
        // Hash the provided password with the same salt
        let saltedPassword = password + salt
        let inputData = Data(saltedPassword.utf8)
        let hashed = SHA256.hash(data: inputData)
        let hashString = hashed.compactMap { String(format: "%02x", $0) }.joined()
        
        // Compare hashes
        return hashString == hash
    }
    
    /// Check if a stored value is already hashed (vs plain text)
    /// - Parameter value: The stored password value
    /// - Returns: True if it appears to be hashed
    static func isHashed(_ value: String) -> Bool {
        // Hashed format is "UUID:64-char-hex"
        let components = value.split(separator: ":")
        return components.count == 2 && components[1].count == 64
    }
}
