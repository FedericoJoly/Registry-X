import SwiftUI
import SwiftData

struct UsersManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var authService
    @Query(sort: \User.username) private var users: [User]
    
    // Auth State
    @State private var isAuthenticatedAsAdmin = false
    @State private var adminUsername = ""
    @State private var adminPassword = ""
    @State private var authError = ""
    
    // User Management State
    @State private var showingCreateUser = false
    @State private var userToEdit: User?
    @State private var showingDeleteAlert = false
    @State private var showSuccessBanner = false
    @State private var showDeleteBanner = false
    @State private var userToDelete: User? = nil // Track user pending deletion
    
    var body: some View {
        ZStack {
            Color(UIColor.systemGray6).ignoresSafeArea()
            
            if isAuthenticatedAsAdmin {
                userListView
            } else {
                adminAuthView
            }
            
            // Success Banner
            if showSuccessBanner {
                VStack {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                        Text("User created. You can login now.")
                            .foregroundStyle(.white)
                            .font(.subheadline)
                            .bold()
                        Spacer()
                    }
                    .padding()
                    .background(Color.green)
                    .cornerRadius(12)
                    .shadow(radius: 5)
                    .padding(.horizontal)
                    .padding(.top, 60) // Account for navigation bar
                    
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(999)
            }
            
            // Delete Banner
            if showDeleteBanner {
                VStack {
                    HStack {
                        Image(systemName: "trash.circle.fill")
                            .foregroundStyle(.white)
                        Text("User deleted successfully.")
                            .foregroundStyle(.white)
                            .font(.subheadline)
                            .bold()
                        Spacer()
                    }
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(12)
                    .shadow(radius: 5)
                    .padding(.horizontal)
                    .padding(.top, 60) // Account for navigation bar
                    
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(999)
            }
        }
        .navigationTitle("Manage Users")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCreateUser) {
            UserFormView(userToEdit: nil, onUserCreated: {
                withAnimation {
                    showSuccessBanner = true
                }
                // Hide banner after 3 seconds
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation {
                        showSuccessBanner = false
                    }
                }
            })
                .presentationDetents([.fraction(0.85)]) // Custom height
                .presentationCornerRadius(20)
        }
        .sheet(item: $userToEdit) { user in
            UserFormView(userToEdit: user)
                .presentationDetents([.fraction(0.85)])
                .presentationCornerRadius(20)
        }
        .alert("Cannot Delete User", isPresented: $showingDeleteAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Create another admin account before deleting this last one.")
        }
        .alert("Delete User", isPresented: Binding(
            get: { userToDelete != nil },
            set: { if !$0 { userToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                userToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let user = userToDelete {
                    confirmDeleteUser(user)
                    userToDelete = nil
                }
            }
        } message: {
            if let user = userToDelete {
                Text("Are you sure you want to delete '\(user.username)'? This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Admin Auth View
    var adminAuthView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            VStack(spacing: 8) {
                Text("Admin Access Required")
                    .font(.title2)
                    .bold()
                Text("Please authenticate with an admin account")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            .padding(.bottom, 20)
            
            VStack(spacing: 15) {
                CustomTextField(icon: "person", placeholder: "Username", text: $adminUsername)
                CustomTextField(icon: "lock", placeholder: "Password", text: $adminPassword, isSecure: true)
            }
            
            if !authError.isEmpty {
                Text(authError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            
            Button(action: authenticateAdmin) {
                Text("Authenticate")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.top, 10)
            
            Spacer()
            Spacer()
        }
        .padding(30)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(20)
        .padding()
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
    
    // MARK: - User List View
    var userListView: some View {
        ScrollView {
            VStack(spacing: 15) {
                ForEach(users) { user in
                    UserRowCard(user: user, onEdit: {
                        userToEdit = user
                    }, onDelete: {
                        userToDelete = user // Show confirmation dialog
                    })
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showingCreateUser = true }) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 16, weight: .bold))
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
    }
    
    private func authenticateAdmin() {
        // Verify locally without logging into the main app
        do {
            let user = try authService.verifyCredentials(username: adminUsername, password: adminPassword, context: modelContext)
            if user.role == .admin {
                isAuthenticatedAsAdmin = true
            } else {
                authError = "Account is not an Admin"
            }
        } catch {
            authError = "Invalid credentials"
        }
    }
    
    private func confirmDeleteUser(_ user: User) {
        // Prevent deleting last admin
        if authService.isLastAdmin(user: user, context: modelContext) {
            showingDeleteAlert = true
            return
        }
        modelContext.delete(user)
        
        // Show deletion confirmation banner
        withAnimation {
            showDeleteBanner = true
        }
        // Hide banner after 3 seconds
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation {
                showDeleteBanner = false
            }
        }
    }
}

// MARK: - Subviews
struct UserRowCard: View {
    let user: User
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            // Avatar (or Initial) could go here
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(user.username)
                        .font(.headline)
                    
                    if user.role == .admin {
                        Label("Admin", systemImage: "shield.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 8)
                            .background(Capsule().fill(Color.blue))
                    }
                }
                
                if !user.email.isEmpty {
                    Text(user.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text("Created: \(user.createdAt.formatted(date: .numeric, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            HStack(spacing: 10) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundStyle(.blue)
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.03), radius: 5, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
}
