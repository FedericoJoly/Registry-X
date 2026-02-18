import SwiftUI
import SwiftData

struct LoginView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var easterEgg = EasterEggManager.shared
    
    @State private var username: String = ""
    @State private var password: String = "" // Was PIN
    @State private var errorMessage: String?
    @State private var showingError: Bool = false
    @State private var showingCreateAccount: Bool = false
    @State private var showingGoogleAlert: Bool = false
    @State private var showSuccessBanner = false
    @State private var showResetConfirmation = false
    @State private var showBiometricPrompt = false
    @State private var biometricAvailable = false
    @State private var biometricType: BiometricAuthManager.BiometricType = .none
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGray6)
                    .ignoresSafeArea()
                
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
                        .padding(.top, 60)
                        
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(999)
                }
                
                // Reset Confirmation Banner
                if showResetConfirmation {
                    VStack {
                        HStack {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .foregroundStyle(.white)
                            Text("Reset Complete")
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
                        .padding(.top, 60)
                        
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(999)
                }
                
                VStack(spacing: 25) {
                    Spacer()
                    
                    // Header
                    VStack(spacing: 5) {
                        Text("REGISTRY X")
                            .font(.custom("Atmospheric", size: 36))
                            .fontWeight(.black) // Fallback weight if font missing
                            .textCase(.uppercase)
                            .tracking(2)
                            .overlay(alignment: .trailing) {
                                // Easter egg tap area on "X"
                                Color.clear
                                    .frame(width: 40, height: 50)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        easterEgg.handleTap()
                                    }
                            }
                        
                        Text("Version 2.0 (2026.2)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 20)
                    
                    Text("Sign in to continue")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    
                    // Inputs
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Username")
                            .font(.footnote)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        
                        TextField("Enter your username", text: $username)
                            .padding()
                            .background(Color(UIColor.systemBackground))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .textInputAutocapitalization(.never)
                    }
                    
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Password")
                            .font(.footnote)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        
                        SecureField("Enter your password", text: $password)
                            .padding()
                            .background(Color(UIColor.systemBackground))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                    
                    // Forgot Password
                    NavigationLink(destination: ForgotPasswordView()) {
                        Label("Forgot Password?", systemImage: "key")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                    }
                    .padding(.top, 5)
                    
                    // Buttons
                    VStack(spacing: 15) {
                        Button(action: login) {
                            HStack {
                                Image(systemName: "arrow.right.square")
                                Text("Sign In")
                            }
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        
                        Button(action: { showingCreateAccount = true }) {
                            Label("Create Account", systemImage: "person.badge.plus")
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(UIColor.systemBackground))
                                .foregroundColor(.blue)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.blue, lineWidth: 1.5)
                                )
                        }
                    }
                    
                    // DIVIDER OR
                    HStack {
                        Rectangle().frame(height: 1).foregroundStyle(.gray.opacity(0.3))
                        Text("or").font(.caption).foregroundStyle(.secondary)
                        Rectangle().frame(height: 1).foregroundStyle(.gray.opacity(0.3))
                    }
                    .padding(.vertical, 10)
                    
                    // Face ID Button - Always show
                    Button(action: loginWithBiometric) {
                        HStack {
                            Image(systemName: "faceid")
                            Text("Sign in with Face ID")
                        }
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    
                    Spacer()
                    
                    // Manage Users
                    NavigationLink(destination: UsersManagementView()) {
                        Label("Manage Users", systemImage: "person.2")
                            .font(.footnote)
                            .foregroundStyle(.gray)
                    }
                }
                .padding(30)
                
                // Easter egg countdown notification
                if easterEgg.showCountdown {
                    VStack {
                        Spacer().frame(height: 140)
                        CountdownNotificationView(text: easterEgg.countdownText)
                        Spacer()
                    }
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.4), value: easterEgg.showCountdown)
                    .zIndex(1003)
                }
                
                // Easter egg music player
                if easterEgg.showPlayer {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            easterEgg.closePlayer()
                        }
                        .zIndex(1001)
                    
                    FloatingMusicPlayerView(albumCoverImage: "CicadaX - Album cover")
                        .zIndex(1002)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
        .alert("Sign In Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .alert("Feature Coming Soon", isPresented: $showingGoogleAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Google login will be available in a future update.")
        }
        .alert("Enable \(BiometricAuthManager.shared.biometricName())?", isPresented: $showBiometricPrompt) {
            Button("Enable", role: .none) {
                // IMPORTANT: Save credentials FIRST, then authenticate
                // If we authenticate first, view switches away before save completes
                enableBiometric()
                // Small delay to ensure save completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    authService.isAuthenticated = true
                }
            }
            Button("Not Now", role: .cancel) {
                // Complete authentication even if user declined biometric
                authService.isAuthenticated = true
            }
        } message: {
            Text("Sign in faster next time using \(BiometricAuthManager.shared.biometricName()).")
        }
        .sheet(isPresented: $showingCreateAccount) {
            UserFormView(userToEdit: nil, onUserCreated: {
                withAnimation {
                    showSuccessBanner = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation {
                        showSuccessBanner = false
                    }
                }
            })
        }
        .onAppear {
            checkBiometricAvailability()
        }
    }
    
    // MARK: - Login Logic
    
    private func login() {
        Task {
            do {
                // Verify credentials but don't authenticate yet
                let user = try authService.verifyCredentials(username: username, password: password, context: modelContext)
                
                // Check if we should show biometric prompt
                // Don't check biometric availability here - iOS will request permission when user enables it
                let hasCredentials = KeychainManager.shared.hasCredentials()
                
                // IMPORTANT: Validate that saved credentials are for an actual user
                // Keychain persists across app deletions, so we need to check if the user still exists
                var credentialsValid = false
                if hasCredentials, let (_, savedUserId) = KeychainManager.shared.loadCredentials() {
                    // Check if this user ID exists in database
                    if let uuid = UUID(uuidString: savedUserId) {
                        let descriptor = FetchDescriptor<User>(predicate: #Predicate { $0.id == uuid })
                        let users = try? modelContext.fetch(descriptor)
                        credentialsValid = users?.isEmpty == false
                    }
                }
                
                if !hasCredentials || !credentialsValid {
                    if hasCredentials && !credentialsValid {
                        KeychainManager.shared.deleteCredentials()
                    }
                    // Set current user but don't authenticate yet
                    await MainActor.run {
                        authService.currentUser = user
                    }
                    // Show prompt - user must respond before we complete login
                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                    await MainActor.run {
                        showBiometricPrompt = true
                    }
                } else {
                    // Complete authentication immediately
                    await MainActor.run {
                        authService.currentUser = user
                        authService.isAuthenticated = true
                    }
                }
            } catch {
                await MainActor.run {
                    showingError = true
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func loginWithBiometric() {
        Task {
            let authenticated = await BiometricAuthManager.shared.authenticate(
                reason: "Sign in to Registry X"
            )

            
            if authenticated {
                // Load credentials from keychain
                guard let (_, userId) = KeychainManager.shared.loadCredentials() else {
                    errorMessage = "Failed to load saved credentials"
                    showingError = true
                    return
                }

                
                // Login with saved credentials
                do {
                    try await authService.loginWithBiometric(userId: userId, modelContext: modelContext)
                } catch {
                    showingError = true
                    errorMessage = error.localizedDescription
                }
            } else {
                errorMessage = "Face ID authentication failed"
                showingError = true
            }
        }
    }
    
    private func enableBiometric() {
        guard let currentUser = authService.currentUser else { return }
        KeychainManager.shared.saveCredentials(
            email: currentUser.email,
            userId: currentUser.id.uuidString
        )
    }
    
    private func checkBiometricAvailability() {
        Task.detached {
            let available = await BiometricAuthManager.shared.isBiometricAvailable()
            let type = await BiometricAuthManager.shared.biometricType()
            
            await MainActor.run {
                biometricAvailable = available
                biometricType = type
            }
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthService())
}
