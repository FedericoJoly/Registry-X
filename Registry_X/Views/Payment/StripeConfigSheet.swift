import SwiftUI

struct StripeConfigSheet: View {
    @Binding var config: StripeConfiguration
    let paymentMethodName: String
    let onSave: () -> Void
    let onCancel: () -> Void
    
    @State private var localConfig: StripeConfiguration

    @FocusState private var focusedField: Field?
    @Environment(AuthService.self) private var authService
    
    enum Field {
        case publishableKey, backendURL, companyName, locationId
    }
    
    init(
        config: Binding<StripeConfiguration>,
        paymentMethodName: String,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        _config = config
        self.paymentMethodName = paymentMethodName
        self.onSave = onSave
        self.onCancel = onCancel
        _localConfig = State(initialValue: config.wrappedValue)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Integration Toggle
                Section {
                    Toggle("Enable Stripe Integration", isOn: $localConfig.isEnabled)
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("When Enabled", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline.bold())
                        Text("• Real-time payment processing\n• Automatic receipts\n• Stripe dashboard tracking")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Label("When Disabled", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.subheadline.bold())
                            .padding(.top, 4)
                        Text("• Manual payment tracking only\n• No real payment processing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("⚡ Stripe Integration")
                }
                
                // Configuration Fields (only if enabled)
                if localConfig.isEnabled {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Publishable Key")
                                .font(.subheadline.bold())
                            TextField("pk_test_...", text: $localConfig.publishableKey)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .publishableKey)
                            Text("Starts with pk_test_ or pk_live_")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Backend URL")
                                .font(.subheadline.bold())
                            TextField("https://your-app.run.app", text: $localConfig.backendURL)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .focused($focusedField, equals: .backendURL)
                            Text("Your Google Cloud Run endpoint")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Terminal Location ID")
                                .font(.subheadline.bold())
                            TextField("tml_...", text: $localConfig.locationId)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .locationId)
                            Text("Required for Tap to Pay feature")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("📋 App Configuration")
                    }
                    

                    
                    // Backend Setup Notice
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Backend Setup Required", systemImage: "server.rack")
                                .font(.subheadline.bold())
                                .foregroundStyle(.blue)
                            
                            Text("You must deploy the backend server with your Stripe Secret Key to process payments.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Text("See documentation for deployment instructions.")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("\(paymentMethodName) Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        config = localConfig
                        onSave()
                    }
                    .bold()
                    .disabled(localConfig.isEnabled && !localConfig.isValid)
                }
            }
        }

    }
}
