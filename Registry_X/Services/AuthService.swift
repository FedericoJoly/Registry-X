import Foundation
import SwiftData
import SwiftUI

@Observable
class AuthService {
    var currentUser: User?
    var isAuthenticated: Bool = false
    
    // In a real app, we might inject a ModelContext here or pass it in methods.
    // For SwiftUI + SwiftData, usually View calls this with context.
    
    func login(username: String, password: String, modelContext: ModelContext) async throws {
        let user = try verifyCredentials(username: username, password: password, context: modelContext)
        currentUser = user
        isAuthenticated = true
    }
    
    func loginWithBiometric(userId: String, modelContext: ModelContext) async throws {
        // Convert String userId back to UUID
        guard let userUUID = UUID(uuidString: userId) else {
            throw AuthError.userNotFound
        }
        
        // Fetch user by ID
        let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == userUUID })
        let users = try modelContext.fetch(descriptor)
        
        guard let user = users.first else {
            throw AuthError.userNotFound
        }
        
        currentUser = user
        isAuthenticated = true
    }
    
    // Check credentials without setting global app state (for Admin Guard)
    func verifyCredentials(username: String, password: String, context: ModelContext) throws -> User {
        let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.username == username })
        let users = try context.fetch(descriptor)
        
        guard let user = users.first else {
            throw AuthError.userNotFound
        }
        
        // Use secure password verification
        if PasswordHashService.verify(password, against: user.passwordHash) {
            return user
        } else {
            throw AuthError.invalidCredentials
        }
    }
    
    func logout() {
        currentUser = nil
        isAuthenticated = false
        // Optionally clear biometric credentials
        // KeychainManager.shared.deleteCredentials()
    }
    
    func resetPassword(email: String, context: ModelContext) throws {
        // 1. Verify Email Exists (Case Insensitive)
        // Fetch all users to robustly check email regardless of case
        let descriptor = FetchDescriptor<User>()
        let users = try context.fetch(descriptor)
        
        let normalizedInput = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        guard let user = users.first(where: { $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedInput }) else {
            throw AuthError.emailNotFound
        }
        
        // 2. Generate Random Password
        let newPassword = String(UUID().uuidString.prefix(8))
        
        // 3. Update User with hashed password
        user.passwordHash = PasswordHashService.hash(newPassword)
        try context.save()
        
        // 4. Send Email (Backend Integration Placeholder)
        sendRecoveryEmail(to: email, fullName: user.fullName, newPassword: newPassword, fromName: "Registry X", fromEmail: "registry-x@newmagicstuff.com")
    }
    
    // MARK: - Email Integration
    
    // Google Cloud Run Backend
    private let googleCloudURL = "https://registry-x-mailer-364250874736.europe-west1.run.app/password-recovery"
    
    private func sendRecoveryEmail(to email: String, fullName: String, newPassword: String, fromName: String = "Registry X", fromEmail: String = "registry-x@newmagicstuff.com") {
        guard let url = URL(string: googleCloudURL) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Backend Payload Schema
        let body: [String: Any] = [
            "email": email,
            "fullName": fullName,
            "temporaryPassword": newPassword,
            "fromName": fromName,
            "fromEmail": fromEmail
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            // Fire and forget (or handle in background task)
            Task {
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                        print("Email sent successfully via Backend!")
                    } else {
                        let errorString = String(data: data, encoding: .utf8) ?? "Unknown"
                        print("Failed to send email: \(errorString)")
                    }
                } catch {
                    print("Network error sending email: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Encoding error: \(error.localizedDescription)")
        }
    }

    
    // Check if a user is the last admin
    func isLastAdmin(user: User, context: ModelContext) -> Bool {
        guard user.role == .admin else { return false }
        do {
            // Fetch all (Predicate for enums is flaky in current SwiftData)
            let descriptor = FetchDescriptor<User>()
            let allUsers = try context.fetch(descriptor)
            let admins = allUsers.filter { $0.role == .admin }
            return admins.count <= 1 && admins.contains(where: { $0.id == user.id })
        } catch {
            return true // Fail safe
        }
    }
}

enum AuthError: Error, LocalizedError {
    case userNotFound
    case invalidCredentials
    case emailNotFound
    
    var errorDescription: String? {
        switch self {
        case .userNotFound: return "User not found."
        case .invalidCredentials: return "Invalid password."
        case .emailNotFound: return "No account found with this email address."
        }
    }
}
