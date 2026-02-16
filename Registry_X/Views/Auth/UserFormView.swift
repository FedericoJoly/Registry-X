import SwiftUI
import SwiftData

struct UserFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var authService
    @Query private var allUsers: [User]
    
    var userToEdit: User? // If nil, create mode
    var onUserCreated: (() -> Void)? = nil // Callback when new user created
    
    // Form States
    @State private var username = ""
    @State private var email = ""
    @State private var fullName = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var role: UserRole = .staff
    
    // Validation
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var isLastAdmin: Bool {
        guard let user = userToEdit else { return false }
        return authService.isLastAdmin(user: user, context: modelContext)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(userToEdit == nil ? "Create User" : "Edit User")
                    .font(.title2)
                    .bold()
                    .padding(.top)
                
                ScrollView {
                    VStack(spacing: 15) {
                        CustomTextField(icon: "person", placeholder: "Username", text: $username, disableAutocorrection: true, textContentType: .username)
                        CustomTextField(icon: "envelope", placeholder: "Email", text: $email, keyboardType: .emailAddress, disableAutocorrection: true, textContentType: .emailAddress)
                        CustomTextField(icon: "person.text.rectangle", placeholder: "Full Name", text: $fullName, autocapitalization: .words, textContentType: .givenName)
                        
                        // Only require password if creating, or if user wants to change it
                        if userToEdit == nil {
                            CustomTextField(icon: "lock", placeholder: "Password", text: $password, isSecure: true, textContentType: .newPassword)
                            CustomTextField(icon: "lock", placeholder: "Confirm Password", text: $confirmPassword, isSecure: true, textContentType: .newPassword)
                        } else {
                            VStack(alignment: .leading) {
                                Text("Change Password (Optional)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                CustomTextField(icon: "lock", placeholder: "New Password", text: $password, isSecure: true, textContentType: .newPassword)
                                CustomTextField(icon: "lock", placeholder: "Confirm New Password", text: $confirmPassword, isSecure: true, textContentType: .newPassword)
                            }
                        }
                        
                        VStack(alignment: .leading) {
                            Text("User Level")
                                .font(.footnote)
                                .bold()
                            
                            HStack(spacing: 15) {
                                RoleButton(title: "Admin", icon: "shield", isSelected: role == .admin) {
                                    role = .admin
                                }
                                RoleButton(title: "Standard", icon: "person.2", isSelected: role == .staff) {
                                    role = .staff
                                }
                                .disabled(allUsers.isEmpty || isLastAdmin) // First user must be admin OR last admin cannot change
                                .opacity((allUsers.isEmpty || isLastAdmin) ? 0.5 : 1.0)
                            }
                            if isLastAdmin {
                                Text("This is the last admin. Create another admin before changing this role.")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .padding(.top, 2)
                            }
                        }
                    }
                    .padding()
                }
                
                HStack(spacing: 15) {
                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(UIColor.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                    
                    Button(action: saveUser) {
                        Text(userToEdit == nil ? "Create" : "Save")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isValid ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(!isValid)
                }
                .padding()
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            if let user = userToEdit {
                // Populate fields
                username = user.username
                email = user.email
                fullName = user.fullName
                role = user.role
                // Password intentionally left blank unless changed
            } else {
                // Business Logic: First user must be admin
                if allUsers.isEmpty {
                    role = .admin
                }
            }
        }
    }
    
    var isValid: Bool {
        if userToEdit == nil {
            return !username.isEmpty && !password.isEmpty && password == confirmPassword
        } else {
            // Editing: always valid unless password is typed but not confirmed
            return !username.isEmpty && (password.isEmpty || password == confirmPassword)
        }
    }
    
    func saveUser() {
        // Validate duplicates
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        if userToEdit == nil {
            // Creating new user: Check if any existing user has this username
            if allUsers.contains(where: { $0.username.lowercased() == normalizedUsername }) {
                errorMessage = "The username '\(username)' is already taken."
                showingError = true
                return
            }
        } else {
            // Editing: Check if any license *other than self* has this username
            if let current = userToEdit, allUsers.contains(where: { $0.id != current.id && $0.username.lowercased() == normalizedUsername }) {
                errorMessage = "The username '\(username)' is already taken."
                showingError = true
                return
            }
        }
        
        if let user = userToEdit {
            user.username = username
            user.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            user.fullName = fullName
            user.role = role
            if !password.isEmpty {
                user.passwordHash = PasswordHashService.hash(password)
            }
            // Context saves automatically or when view dismisses usually
        } else {
            let newUser = User(
                username: username,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                fullName: fullName,
                passwordHash: PasswordHashService.hash(password),
                role: role
            )
            modelContext.insert(newUser)
            
            // Dismiss first, then notify parent so banner shows after sheet is gone
            dismiss()
            
            // Notify parent that user was created
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onUserCreated?()
            }
            return
        }
        dismiss()
    }
}

// Helper Views
struct CustomTextField: View {
    var icon: String
    var placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .never
    var disableAutocorrection: Bool = false
    var textContentType: UITextContentType? = nil
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.gray)
                .frame(width: 20)
            
            if isSecure {
                SecureField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .autocorrectionDisabled(disableAutocorrection)
                    .textInputAutocapitalization(autocapitalization)
                    .textContentType(textContentType)
            } else {
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(autocapitalization)
                    .keyboardType(keyboardType)
                    .autocorrectionDisabled(disableAutocorrection)
                    .textContentType(textContentType)
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

struct RoleButton: View {
    var title: String
    var icon: String
    var isSelected: Bool
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline)
            .bold()
            .frame(maxWidth: .infinity)
            .padding()
            .background(isSelected ? Color.blue : Color(UIColor.systemGray5)) // Blue when selected
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
            )
        }
    }
}
