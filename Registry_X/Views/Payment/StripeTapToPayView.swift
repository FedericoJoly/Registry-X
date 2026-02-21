import SwiftUI
import Combine
import StripeTerminal
import CoreLocation

// MARK: - Tap to Pay Coordinator

@MainActor
class TapToPayCoordinator: NSObject, ObservableObject, ConnectionTokenProvider, DiscoveryDelegate, TerminalDelegate, TapToPayReaderDelegate, CLLocationManagerDelegate {
    @Published var paymentStatus: PaymentStatus = .initializing
    @Published var errorMessage: String?
    @Published var updateProgress: Float = 0.0
    @Published var isUpdating: Bool = false
    
    private var locationManager: CLLocationManager?
    private static var isTerminalInitialized = false
    private var isCanceled = false
    
    // Changing to nonisolated let to allow access from nonisolated context
    nonisolated private let backendURL: String
    private var amount: Decimal
    private var currency: String
    private var paymentDescription: String
    private var locationId: String
    private var paymentIntentId: String?
    private var onSuccess: (String) -> Void
    private var onCancel: () -> Void
    private var discoveredReader: Reader?
    
    enum PaymentStatus {
        case initializing
        case updating
        case readyToTap
        case processing
        case success
        case failed
    }
    
    init(backendURL: String, amount: Decimal, currency: String, description: String, locationId: String, onSuccess: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.backendURL = backendURL
        self.amount = amount
        self.currency = currency
        self.paymentDescription = description
        self.locationId = locationId
        self.onSuccess = onSuccess
        self.onCancel = onCancel
        super.init()
    }
    
    nonisolated func initializeTerminal() {
        Task { @MainActor in
            // Initialize Terminal SDK first - needed for cleanup even if location fails
            // Only initialize once per app session - SDK enforces this
            if !TapToPayCoordinator.isTerminalInitialized {
                Terminal.initWithTokenProvider(self)
                TapToPayCoordinator.isTerminalInitialized = true
            }
            
            // Check location permission - STOP if not authorized
            guard await self.checkLocationPermission() else {
                return // Location denied or restricted
            }
            
            // Configure for Tap to Pay discovery
            do {
                let config = try TapToPayDiscoveryConfigurationBuilder().build()
                
                Terminal.shared.discoverReaders(config, delegate: self) { error in
                    Task { @MainActor in
                        if let error = error {
                            self.errorMessage = "Discovery failed: \(error.localizedDescription)"
                            self.paymentStatus = .failed
                        }
                    }
                }
            } catch {
                self.errorMessage = "Configuration failed: \(error.localizedDescription)"
                self.paymentStatus = .failed
            }
        }
    }
    
    private func checkLocationPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            let manager = CLLocationManager()
            self.locationManager = manager
            manager.delegate = self
            
            let status = manager.authorizationStatus
            
            switch status {
            case .notDetermined:
                // Request permission and wait
                manager.requestWhenInUseAuthorization()
                // Give it a moment to process
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let newStatus = manager.authorizationStatus
                    if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                        continuation.resume(returning: true)
                    } else {
                        self.errorMessage = "Tap to Pay requires Location Services. Go to Settings → Privacy & Security → Location Services and enable it. Then activate 'Tap to Pay on iPhone Screen Lock' in Settings → Registry X."
                        self.paymentStatus = .failed
                        continuation.resume(returning: false)
                    }
                }
            case .denied, .restricted:
                self.errorMessage = "Tap to Pay requires Location Services. Go to Settings → Privacy & Security → Location Services and enable it. Then activate 'Tap to Pay on iPhone Screen Lock' in Settings → Registry X."
                self.paymentStatus = .failed
                continuation.resume(returning: false)
            case .authorizedWhenInUse, .authorizedAlways:
                continuation.resume(returning: true)
            @unknown default:
                continuation.resume(returning: false)
            }
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                self.errorMessage = "Tap to Pay requires Location Services. Go to Settings → Privacy & Security → Location Services and enable it. Then activate 'Tap to Pay on iPhone Screen Lock' in Settings → Registry X."
                self.paymentStatus = .failed
            }
        }
    }
    
    // MARK: - ConnectionTokenProvider
    
    nonisolated func fetchConnectionToken(_ completion: @escaping ConnectionTokenCompletionBlock) {
        guard let url = URL(string: "\(backendURL)/connection-token") else {
            completion(nil, NSError(domain: "InvalidURL", code: -1))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let secret = json["secret"] as? String else {
                completion(nil, NSError(domain: "InvalidResponse", code: -1))
                return
            }
            
            completion(secret, nil)
        }.resume()
    }
    
    // MARK: - DiscoveryDelegate
    
    nonisolated func terminal(_ terminal: Terminal, didUpdateDiscoveredReaders readers: [Reader]) {
        guard let reader = readers.first else { return }
        
        Task { @MainActor in
            // Ignore if user canceled
            if self.isCanceled { return }
            
            discoveredReader = reader
            
            // Connect to reader
            do {
                let config = try TapToPayConnectionConfigurationBuilder(delegate: self, locationId: self.locationId).build()
                
                do {
                    let _ = try await Terminal.shared.connectReader(reader, connectionConfig: config)
                    
                    // Ignore if user canceled
                    if self.isCanceled { return }
                    
                    // Reader connected, collect payment
                    await self.collectPayment()
                } catch {
                    // Ignore if user canceled
                    if self.isCanceled { return }
                    
                    self.errorMessage = "Connection failed: \(error.localizedDescription)"
                    self.paymentStatus = .failed
                }
            } catch {
                self.errorMessage = "Connection config failed: \(error.localizedDescription)"
                self.paymentStatus = .failed
            }
        }
    }
    
    // MARK: - TerminalDelegate
    
    nonisolated func terminal(_ terminal: Terminal, didReportUnexpectedReaderDisconnect reader: Reader) {
        Task { @MainActor in
            // Ignore if user canceled
            if self.isCanceled { return }
            
            // Don't show any error - disconnect is expected when canceling or retrying
            // Real payment errors are caught elsewhere
        }
    }
    
    // MARK: - ReaderSoftwareUpdateDelegate
    
    nonisolated func terminal(_ terminal: Terminal, didStartInstallingUpdate update: ReaderSoftwareUpdate, cancelable: Cancelable?) {
        Task { @MainActor in
            self.isUpdating = true
            self.paymentStatus = .updating
            self.updateProgress = 0.0
        }
    }
    
    nonisolated func terminal(_ terminal: Terminal, didReportReaderSoftwareUpdateProgress progress: Float) {
        Task { @MainActor in
            self.updateProgress = progress
        }
    }
    
    nonisolated func terminal(_ terminal: Terminal, didFinishInstallingUpdate update: ReaderSoftwareUpdate?, error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.errorMessage = "Update failed: \(error.localizedDescription)"
                self.paymentStatus = .failed
                self.isUpdating = false
            } else {
                self.isUpdating = false
                // Don't change status here - connection flow will continue
            }
        }
    }
    
    // MARK: - TapToPayReaderDelegate
    
    nonisolated func tapToPayReader(_ reader: Reader, didReportReaderSoftwareUpdateProgress progress: Float) {
        // Handle update progress
    }
    
    nonisolated func tapToPayReader(_ reader: Reader, didStartInstallingUpdate update: ReaderSoftwareUpdate, cancelable: Cancelable?) {
        Task { @MainActor in
        }
    }
    
    nonisolated func tapToPayReader(_ reader: Reader, didFinishInstallingUpdate update: ReaderSoftwareUpdate?, error: Error?) {
        Task { @MainActor in
            if error != nil {
            } else {
            }
        }
    }
    
    nonisolated func tapToPayReader(_ reader: Reader, didRequestReaderInput inputOptions: ReaderInputOptions) {
        Task { @MainActor in
        }
    }
    
    nonisolated func tapToPayReader(_ reader: Reader, didRequestReaderDisplayMessage displayMessage: ReaderDisplayMessage) {
        Task { @MainActor in
        }
    }
    
    nonisolated func reader(_ reader: Reader, didDisconnect reason: DisconnectReason) {
        Task { @MainActor in
            // Ignore disconnect if payment already succeeded (cleanup calls disconnectReader
            // after success — triggering this delegate should not flash a red error screen)
            // or if this was an intentional cancel (isCanceled already handles cleanup).
            guard paymentStatus != .success && !isCanceled else { return }
            self.errorMessage = "Reader disconnected: \(reason)"
            self.paymentStatus = .failed
        }
    }
    
    // MARK: - Payment Collection
    
    func collectPayment() async {
        paymentStatus = .readyToTap
        
        do {
            // Create payment intent via backend
            let service = StripeNetworkService(backendURL: backendURL)
            let response = try await service.createTerminalPaymentIntent(
                amount: amount,
                currency: currency,
                description: paymentDescription,
                metadata: ["source": "Tap_to_Pay"]
            )
            
            self.paymentIntentId = response.intentId
            
            // Retrieve the payment intent from Stripe
            do {
                let paymentIntent = try await Terminal.shared.retrievePaymentIntent(clientSecret: response.clientSecret)
                
                // Collect payment method
                Terminal.shared.collectPaymentMethod(paymentIntent) { collectResult, collectError in
                    Task { @MainActor in
                        if let error = collectError {
                            // Check if this is a user cancellation
                            let errorMessage = error.localizedDescription
                            if errorMessage.contains("canceled") || errorMessage.contains("cancelled") {
                                // User canceled - dismiss cleanly
                                self.isCanceled = true
                                self.onCancel()
                                return
                            }
                            
                            // Real error - show it
                            self.errorMessage = errorMessage
                            self.paymentStatus = .failed
                            return
                        }
                        
                        guard let collectedIntent = collectResult else { return }
                        
                        // Update to processing
                        self.paymentStatus = .processing
                        
                        // Confirm payment
                        Terminal.shared.confirmPaymentIntent(collectedIntent) { confirmResult, confirmError in
                            Task { @MainActor in
                                if let error = confirmError {
                                    // Check if this is a user cancellation
                                    let errorMessage = error.localizedDescription
                                    if errorMessage.contains("canceled") || errorMessage.contains("cancelled") {
                                        // User canceled - dismiss cleanly
                                        self.isCanceled = true
                                        self.onCancel()
                                        return
                                    }
                                    
                                    // Real error - show it
                                    self.errorMessage = errorMessage
                                    self.paymentStatus = .failed
                                    return
                                }
                                
                                // Success!
                                self.paymentStatus = .success
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                if let intentId = self.paymentIntentId {
                                    self.onSuccess(intentId)
                                    // Auto-dismiss so the caller can chain the next step
                                    self.cleanup()
                                }
                            }
                        }
                    }
                }
            } catch {
                self.errorMessage = error.localizedDescription
                self.paymentStatus = .failed
            }
            
        } catch {
            errorMessage = error.localizedDescription
            paymentStatus = .failed
        }
    }
    
    func cancelPayment() {
        // Mark as canceled to prevent delegate callbacks from continuing
        isCanceled = true
        // Clear any error state to avoid showing "Payment Failed"
        errorMessage = nil
        // Reset to initializing so UI doesn't show failed state
        paymentStatus = .initializing
        cleanup()
    }
    
    func cleanup() {
        // Only disconnect if there's actually a connected reader
        if Terminal.shared.connectedReader != nil {
            Terminal.shared.disconnectReader { _ in }
        }
    }
    
    func retryPayment() {
        // Reset cancel flag
        isCanceled = false
        errorMessage = nil
        paymentStatus = .initializing
        
        // Disconnect any connected reader first
        if Terminal.shared.connectedReader != nil {
            Terminal.shared.disconnectReader { error in
                Task { @MainActor in
                    // After disconnect, retry full initialization including location check
                    self.initializeTerminal()
                }
            }
        } else {
            // No reader connected, just retry
            initializeTerminal()
        }
    }
}

// MARK: - SwiftUI View

struct StripeTapToPayView: View {
    let amount: Decimal
    let currency: String
    let description: String
    let backendURL: String
    let locationId: String
    let onSuccess: (String) -> Void
    let onCancel: () -> Void
    
    @StateObject private var coordinator: TapToPayCoordinator
    @Environment(\.dismiss) private var dismiss
    
    init(amount: Decimal, currency: String, description: String, backendURL: String, locationId: String = "", onSuccess: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.amount = amount
        self.currency = currency
        self.description = description
        self.backendURL = backendURL
        self.locationId = locationId
        self.onSuccess = onSuccess
        self.onCancel = onCancel
        
        _coordinator = StateObject(wrappedValue: TapToPayCoordinator(
            backendURL: backendURL,
            amount: amount,
            currency: currency,
            description: description,
            locationId: locationId,
            onSuccess: onSuccess,
            onCancel: onCancel
        ))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                // Status Icon
                Group {
                    switch coordinator.paymentStatus {
                    case .initializing:
                        ProgressView()
                            .scaleEffect(2)
                    case .updating:
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                                .frame(width: 100, height: 100)
                            
                            Circle()
                                .trim(from: 0, to: CGFloat(coordinator.updateProgress))
                                .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .frame(width: 100, height: 100)
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 0.2), value: coordinator.updateProgress)
                            
                            VStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.blue)
                                Text("\(Int(coordinator.updateProgress * 100))%")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    case .readyToTap:
                        Image(systemName: "wave.3.right")
                            .font(.system(size: 80))
                            .foregroundStyle(.blue)
                            .symbolEffect(.variableColor.iterative.reversing)
                    case .processing:
                        ProgressView()
                            .scaleEffect(2)
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.green)
                    case .failed:
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.red)
                    }
                }
                .frame(height: 100)
                
                // Status Text
                VStack(spacing: 8) {
                    Text(statusTitle)
                        .font(.title2.bold())
                    
                    if coordinator.paymentStatus == .updating {
                        Text("First time setup - this takes about 30 seconds")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("\(formattedAmount) \(currency.uppercased())")
                        .font(.title.bold())
                    
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Error Message
                if let error = coordinator.errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // Instructions or Actions
                VStack(spacing: 16) {
                    if coordinator.paymentStatus == .readyToTap {
                        InstructionCard(
                            icon: "contactless",
                            title: "Hold card near top of iPhone",
                            subtitle: "Payment will process automatically"
                        )
                    } else if coordinator.paymentStatus == .failed {
                        // Show numbered setup buttons if error is about location
                        if let error = coordinator.errorMessage, error.contains("Location Services") {
                            VStack(spacing: 12) {
                                Button {
                                    // Open root Settings app (not Registry X settings)
                                    if let url = URL(string: "App-prefs:root") {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    HStack {
                                        Text("1️⃣")
                                            .font(.title2)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Enable Location Services")
                                                .font(.subheadline.bold())
                                            Text("Go to: Privacy & Security → Location Services → ON")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding()
                                    .background(Color(.systemBackground))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.blue, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                                
                                Button {
                                    // Open Registry X settings
                                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(settingsUrl)
                                    }
                                } label: {
                                    HStack {
                                        Text("2️⃣")
                                            .font(.title2)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Enable Tap to Pay Screen Lock")
                                                .font(.subheadline.bold())
                                            Text("Toggle on in Registry X settings")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding()
                                    .background(Color(.systemBackground))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.blue, lineWidth: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                                
                                Button("Try Again") {
                                    coordinator.retryPayment()
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.horizontal)
                        } else {
                            Button("Try Again") {
                                coordinator.retryPayment()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    
                    if coordinator.paymentStatus != .success && coordinator.paymentStatus != .processing {
                        Button("Cancel") {
                            coordinator.cancelPayment()
                            dismiss()
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Tap to Pay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if coordinator.paymentStatus != .processing && coordinator.paymentStatus != .success {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            coordinator.cancelPayment()
                            dismiss()
                        }
                    }
                }
            }
        }
        .task {
            coordinator.initializeTerminal()
        }
        .onDisappear {
            coordinator.cleanup()
        }
    }
    
    private var statusTitle: String {
        switch coordinator.paymentStatus {
        case .initializing:
            return "Initializing..."
        case .updating:
            return "Updating Reader..."
        case .readyToTap:
            return "Ready to Accept Payment"
        case .processing:
            return "Processing..."
        case .success:
            return "Payment Successful!"
        case .failed:
            return "Payment Failed"
        }
    }
    
    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSNumber) ?? "\(amount)"
    }
}

// MARK: - Supporting Views

struct InstructionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}
