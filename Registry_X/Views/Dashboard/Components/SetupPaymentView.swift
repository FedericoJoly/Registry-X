import SwiftUI
import SwiftData

struct SetupPaymentView: View {
    @Binding var draft: DraftEventSettings
    @Binding var bizumPhoneNumber: String
    var isLocked: Bool
    var onRefreshRates: () -> Void
    
    @State private var showingAddCurrency = false
    @State private var showingDeleteAlert = false
    @State private var currencyIdToDelete: UUID?
    @State private var editingRateID: UUID? = nil
    @State private var configuringMethod: PaymentMethodOption? = nil
    @State private var showingStripeConfig = false
    @State private var showingBackendTest = false

    
    @Environment(AuthService.self) private var authService
    
    // Computed property to check if company data is configured
    private var isCompanyDataConfigured: Bool {
        return !draft.companyName.isEmpty &&
               !draft.fromName.isEmpty &&
               !draft.fromEmail.isEmpty
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 15) {
                // CARD: CURRENCIES (Unified Box)
                VStack(alignment: .leading, spacing: 12) {
                    // Row 1: Title only
                    Text("Currencies")
                        .font(.body)
                    
                    // Row 2: Refresh Rates and Add Currency Buttons
                    HStack(spacing: 12) {
                        // Refresh Rates Button (smaller, 50%)
                        Button(action: onRefreshRates) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                                    Text("Refresh Rates")
                                        .font(.caption)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(isLocked ? Color.gray.opacity(0.3) : Color.blue.opacity(0.1))
                            .foregroundColor(isLocked ? .gray : .blue)
                            .cornerRadius(8)
                        }
                        .disabled(isLocked)
                        
                        // Add Currency Button
                        Button(action: { showingAddCurrency = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.caption)
                                    Text("Add Currency")
                                        .font(.caption)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(isLocked ? Color.gray.opacity(0.5) : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .disabled(isLocked)
                    }
                    
                    // Last Updated Footer
                    if let date = draft.ratesLastUpdated {
                        Text("Last updated: \(date.formatted(date: .numeric, time: .standard))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    // Column Headers
                    HStack(spacing: 8) {
                        Text("Code")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .center)
                        
                        Text("Symbol")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .center)
                        
                        Text("Rate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .center)
                        
                        Text("Status")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .center)
                        
                        Text("Main")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .center)
                        
                        // Space for delete button
                        Color.clear
                            .frame(width: 32)
                    }
                    
                    Divider()
                    
                    // Currency Cards List
                    // Use custom Binding to avoid index-based binding issues
                    ForEach(draft.currencies, id: \.id) { currency in
                        CurrencyCard(
                            currency: Binding(
                                get: {
                                    // Always look up by ID to get current state
                                    draft.currencies.first(where: { $0.id == currency.id }) ?? currency
                                },
                                set: { newValue in
                                    // Update by ID to avoid index issues
                                    if let index = draft.currencies.firstIndex(where: { $0.id == currency.id }) {
                                        draft.currencies[index] = newValue
                                    }
                                }
                            ),
                            draft: $draft,
                            isLocked: isLocked,
                            isEditing: editingRateID == currency.id,
                            canDelete: !currency.isDefault && !currency.isMain && draft.currencies.count > 1,
                            onMainToggle: {
                                setMainCurrency(currency.id)
                            },
                            onDelete: {
                                currencyIdToDelete = currency.id
                                showingDeleteAlert = true
                            },
                            onRateEdit: {
                                editingRateID = currency.id
                            },
                            onRateSave: {
                                // Mark as manual FIRST using copy-modify-reassign pattern
                                // This ensures the binding properly updates the parent
                                var updatedDraft = draft
                                if let index = updatedDraft.currencies.firstIndex(where: { $0.id == currency.id }) {
                                    updatedDraft.currencies[index].isManual = true
                                }
                                updatedDraft.changeId = UUID()
                                draft = updatedDraft // Trigger binding update
                                editingRateID = nil
                            }
                        )
                    }
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                .disabled(isLocked)
                .opacity(isLocked ? 0.6 : 1.0)
                
                // CARD: METHODS
                VStack(alignment: .leading, spacing: 12) {
                    Text("Methods")
                        .font(.body)
                    
                    VStack(spacing: 0) {
                        ForEach($draft.paymentMethods) { $method in
                            HStack(spacing: 8) {
                                // Column 1: Icon + Name (left aligned)
                                HStack(spacing: 8) {
                                    Image(systemName: method.icon)
                                        .font(.title3)
                                        .foregroundStyle(method.color)
                                        .frame(width: 30)
                                    
                                    Text(method.name)
                                        .font(.body)
                                }
                                
                                Spacer()
                                
                                // Column 2: Toggle
                                Toggle("", isOn: Binding(
                                    get: { method.isEnabled },
                                    set: { newValue in
                                        // Special validation for Bizum: require phone number
                                        if method.name == "Bizum" && newValue && bizumPhoneNumber.isEmpty {
                                            // Don't enable without phone number
                                            return
                                        }
                                        
                                        // Update draft atomically
                                        if let index = draft.paymentMethods.firstIndex(where: { $0.id == method.id }) {
                                            var updatedDraft = draft
                                            updatedDraft.paymentMethods[index].isEnabled = newValue
                                            updatedDraft.changeId = UUID()
                                            draft = updatedDraft
                                        }
                                    }
                                ))
                                    .labelsHidden()
                                    .scaleEffect(0.7)
                                    .disabled(
                                        // Disable if last enabled method
                                        (method.isEnabled && draft.paymentMethods.filter { $0.isEnabled }.count == 1) ||
                                        // Disable Bizum if no phone number
                                        (method.name == "Bizum" && bizumPhoneNumber.isEmpty)
                                    )
                                    .onChange(of: bizumPhoneNumber) { oldValue, newValue in
                                        // Auto-disable Bizum toggle when phone number is cleared
                                        if method.name == "Bizum" && newValue.isEmpty && method.isEnabled {
                                            method.isEnabled = false
                                            draft.changeId = UUID() // Trigger change detection
                                        }
                                    }
                                
                                // Column 3: Cog icon (all methods)
                                Button(action: {
                                    configuringMethod = method
                                }) {
                                    Image(systemName: "gearshape")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.gray.opacity(0.5))
                                        .frame(width: 30)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 12)
                            
                            // Divider if not last
                            if method.id != draft.paymentMethods.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                .disabled(isLocked)
                .opacity(isLocked ? 0.6 : 1.0)
                
                // CARD: PROVIDERS
                VStack(alignment: .leading, spacing: 12) {
                    Text("Providers")
                        .font(.body)
                    
                    // Stripe Provider
                    HStack(spacing: 12) {
                        Image(systemName: "creditcard.and.123")
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .frame(width: 30)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Stripe")
                                .font(.body.bold())
                            
                            if draft.stripeIntegrationEnabled && 
                               !draft.stripePublishableKey.isEmpty && 
                               !draft.stripeBackendURL.isEmpty {
                                Text("✓ Configured")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else if draft.stripeIntegrationEnabled {
                                Text("⚠ Incomplete")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else {
                                Text("Not configured")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        
                        Spacer()
                        
                        // Test Backend Button (only show if configured)
                        if draft.stripeIntegrationEnabled && 
                           !draft.stripeBackendURL.isEmpty {
                            Button(action: {
                                showingBackendTest = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "network")
                                        .font(.system(size: 14))
                                    Text("Test")
                                        .font(.caption)
                                }
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.borderless)
                        }
                        
                        Button(action: {
                            showingStripeConfig = true
                        }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 16))
                                .foregroundStyle(.gray.opacity(0.5))
                                .frame(width: 30)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 12)
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                .disabled(isLocked)
                .opacity(isLocked ? 0.6 : 1.0)
                
                // CARD: RECEIPTS
                VStack(alignment: .leading, spacing: 12) {
                    Text("Receipts")
                        .font(.body)
                    
                    VStack(spacing: 0) {
                        // Get payment methods (excluding QR - auto receipt)
                        ForEach(draft.paymentMethods.filter { $0.name != "QR Code" }, id: \.id) { method in
                            HStack(spacing: 8) {
                                // Column 1: Icon + Name
                                HStack(spacing: 8) {
                                    Image(systemName: method.icon)
                                        .font(.title3)
                                        .foregroundStyle(method.color)
                                        .frame(width: 30)
                                    
                                    Text(method.name)
                                        .font(.body)
                                }
                                
                                Spacer()
                                
                                // Column 2: Receipt Toggle
                                Toggle("", isOn: Binding(
                                    get: { draft.receiptSettings[method.name] ?? false },
                                    set: { newValue in
                                        // Update draft atomically - EXACT pattern from payment methods
                                        var updatedDraft = draft
                                        updatedDraft.receiptSettings[method.name] = newValue
                                        updatedDraft.changeId = UUID()
                                        draft = updatedDraft
                                    }
                                ))
                                    .labelsHidden()
                                    .scaleEffect(0.7)
                                    .disabled(!isCompanyDataConfigured)
                            }
                            .padding(.vertical, 12)
                            
                            // Divider if not last
                            if method.id != draft.paymentMethods.filter({ $0.name != "QR Code" }).last?.id {
                                Divider()
                            }
                        }
                    }
                    .background(Color(UIColor.tertiarySystemFill))
                    .cornerRadius(10)
                    
                    if !isCompanyDataConfigured {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Company information required")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                                Text("Configure Company settings (name, FROM email) before enabling receipts.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    } else {
                        Text("When enabled, customers will be asked if they need a receipt after payment.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                .disabled(isLocked)
                .opacity(isLocked ? 0.6 : 1.0)
            }
            .padding(.horizontal, 16)
        }
        .sheet(isPresented: $showingAddCurrency) {
            AddCurrencySheet(
                existingCurrencies: draft.currencies,
                mainCurrencyCode: draft.currencies.first(where: { $0.isMain })?.code ?? draft.currencyCode,
                onAdd: { newCurrency in
                    var curr = newCurrency
                    curr.sortOrder = draft.currencies.count
                    draft.currencies.append(curr)
                    // Force change detection by updating changeId
                    draft.changeId = UUID()
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .alert("Delete Currency?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let id = currencyIdToDelete {
                    // Prevent deletion of main currency
                    guard !draft.currencies.contains(where: { $0.id == id && $0.isMain }) else { return }
                    // Prevent deletion of the last currency
                    guard draft.currencies.count > 1 else { return }
                    
                    // Perform deletion on next run loop to avoid SwiftUI update conflicts
                    DispatchQueue.main.async {
                        withAnimation {
                            draft.currencies.removeAll { $0.id == id }
                            // Force change detection by updating changeId
                            draft.changeId = UUID()
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this currency?")
        }
        .sheet(item: $configuringMethod) { method in
            if let index = draft.paymentMethods.firstIndex(where: { $0.id == method.id }) {
                PaymentMethodConfigSheet(
                    method: $draft.paymentMethods[index],
                    currencies: draft.currencies,
                    stripeConfig: Binding(
                        get: {
                            StripeConfiguration(
                                isEnabled: draft.stripeIntegrationEnabled,
                                publishableKey: draft.stripePublishableKey,
                                backendURL: draft.stripeBackendURL,
                                companyName: draft.companyName.isEmpty ? draft.stripeCompanyName : draft.companyName,
                                locationId: draft.stripeLocationId
                            )
                        },
                        set: { newConfig in
                            draft.stripeIntegrationEnabled = newConfig.isEnabled
                            draft.stripePublishableKey = newConfig.publishableKey
                            draft.stripeBackendURL = newConfig.backendURL
                            // Keep stripeCompanyName in sync for backward compatibility
                            if !draft.companyName.isEmpty {
                                draft.stripeCompanyName = draft.companyName
                            }
                            draft.stripeLocationId = newConfig.locationId
                        }
                    ),
                    bizumPhoneNumber: $bizumPhoneNumber,
                    onSave: {
                        // Trigger change detection
                        draft.changeId = UUID()
                    }
                )
            }
        }
        .sheet(isPresented: $showingStripeConfig) {
            StripeConfigSheet(
                config: Binding(
                    get: {
                        StripeConfiguration(
                            isEnabled: draft.stripeIntegrationEnabled,
                            publishableKey: draft.stripePublishableKey,
                            backendURL: draft.stripeBackendURL,
                            companyName: draft.companyName,
                            locationId: draft.stripeLocationId
                        )
                    },
                    set: { newConfig in
                        draft.stripeIntegrationEnabled = newConfig.isEnabled
                        draft.stripePublishableKey = newConfig.publishableKey
                        draft.stripeBackendURL = newConfig.backendURL
                        draft.companyName = newConfig.companyName
                        draft.stripeLocationId = newConfig.locationId
                        draft.changeId = UUID()
                    }
                ),
                paymentMethodName: "Stripe",
                onSave: {
                    showingStripeConfig = false
                },
                onCancel: {
                    showingStripeConfig = false
                }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingBackendTest) {
            if !draft.stripeBackendURL.isEmpty {
                StripeBackendTestView(backendURL: draft.stripeBackendURL)
            } else {
                Text("No backend URL configured")
            }
        }
    }
    
    // MARK: - Helpers
    
    private func setMainCurrency(_ id: UUID) {
        guard let newMainIndex = draft.currencies.firstIndex(where: { $0.id == id }) else { return }
        guard let oldMainIndex = draft.currencies.firstIndex(where: { $0.isMain }) else { return }
        
        // If already main, do nothing
        if newMainIndex == oldMainIndex { return }
        
        // Get the conversion factor: the new main's current rate
        // All other rates need to be divided by this to maintain relative proportions
        let conversionFactor = draft.currencies[newMainIndex].rate
        
        // Prevent division by zero
        guard conversionFactor > 0 else { return }
        
        // Update all currencies
        for index in draft.currencies.indices {
            if index == newMainIndex {
                // Setting as new main
                draft.currencies[index].isMain = true
                draft.currencies[index].isEnabled = true // Auto-enable main
                draft.currencies[index].rate = 1.0 // Main is always 1.0
            } else if index == oldMainIndex {
                // Unsetting old main - calculate its rate relative to new main
                draft.currencies[index].isMain = false
                // Only recalculate if not manually set
                if !draft.currencies[index].isManual {
                    // Old main was 1.0, new rate is 1.0 / conversionFactor
                    draft.currencies[index].rate = 1.0 / conversionFactor
                }
            } else {
                // Update other currencies: divide by conversion factor
                // Only recalculate if not manually set
                if !draft.currencies[index].isManual {
                    draft.currencies[index].rate = draft.currencies[index].rate / conversionFactor
                }
            }
        }
    }
}

// MARK: - Currency Card Component (Single Line)

struct CurrencyCard: View {
    @Binding var currency: DraftCurrency
    @Binding var draft: DraftEventSettings
    var isLocked: Bool
    var isEditing: Bool
    var canDelete: Bool
    var onMainToggle: () -> Void
    var onDelete: () -> Void
    var onRateEdit: () -> Void
    var onRateSave: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Code
            Text(currency.code)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(width: 50, alignment: .center)
            
            // Symbol
            Text(currency.symbol)
                .font(.subheadline)
                .frame(width: 50, alignment: .center)
            
            // Rate
            if currency.isMain {
                Text("1.00")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .center)
            } else if isEditing {
                HStack(spacing: 4) {
                    TextField("Rate", value: $currency.rate, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                        .font(.subheadline)
                        .monospaced()
                        .multilineTextAlignment(.center)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    
                    Button(action: onRateSave) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .frame(width: 80, alignment: .center)
            } else {
                HStack(spacing: 2) {
                    if currency.isManual {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.orange)
                    }
                    
                    Text(currency.rate.formatted(.number.precision(.fractionLength(2))))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .monospaced()
                }
                .frame(width: 80, alignment: .center)
                .onLongPressGesture {
                    if !isLocked && !currency.isMain {
                        onRateEdit()
                    }
                }
            }
            
            // Enabled Toggle
            Toggle("", isOn: $currency.isEnabled)
                .labelsHidden()
                .tint(.green)
                .scaleEffect(0.7)
                .frame(width: 40)
                .disabled(currency.isMain) // Main is always enabled
            
            // Main Toggle
            Toggle("", isOn: Binding(
                get: {
                    // Always look up current state by ID
                    draft.currencies.first(where: { $0.id == currency.id })?.isMain ?? false
                },
                set: { _ in
                    onMainToggle()
                }
            ))
            .labelsHidden()
            .tint(.blue)
            .scaleEffect(0.7)
            .frame(width: 40)
            
            // Delete Button
            if canDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .frame(width: 32)
                .disabled(isLocked)
            } else {
                Color.clear
                    .frame(width: 32)
            }
        }
        .padding(.vertical, 8)
        .background(Color(UIColor.systemGray6).opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - Add Currency Sheet

struct AddCurrencySheet: View {
    @Environment(\.dismiss) private var dismiss
    var existingCurrencies: [DraftCurrency]
    var mainCurrencyCode: String
    var onAdd: (DraftCurrency) -> Void
    
    @State private var showingCustomForm = false
    @State private var searchText = ""
    @State private var selectedCurrencies = Set<String>()
    @State private var customCode = ""
    @State private var customSymbol = ""
    @State private var customName = ""
    @State private var customRate: Decimal = 1.0
    @State private var isFetchingRate = false
    @State private var rateAutoFetched = false
    
    private let currencyService = CurrencyService()
    
    // 21 most popular world currencies (alphabetically ordered after USD, EUR, GBP)
    let popularCurrencies: [(code: String, symbol: String, name: String)] = [
        ("USD", "$", "US Dollar"),
        ("EUR", "€", "Euro"),
        ("GBP", "£", "British Pound"),
        ("ARS", "$", "Argentine Peso"),
        ("AUD", "$", "Australian Dollar"),
        ("BRL", "R$", "Brazilian Real"),
        ("CAD", "$", "Canadian Dollar"),
        ("CNY", "¥", "Chinese Yuan"),
        ("HKD", "HK$", "Hong Kong Dollar"),
        ("INR", "₹", "Indian Rupee"),
        ("JPY", "¥", "Japanese Yen"),
        ("MXN", "$", "Mexican Peso"),
        ("NZD", "$", "New Zealand Dollar"),
        ("NOK", "kr", "Norwegian Krone"),
        ("RUB", "₽", "Russian Ruble"),
        ("SGD", "S$", "Singapore Dollar"),
        ("ZAR", "R", "South African Rand"),
        ("KRW", "₩", "South Korean Won"),
        ("SEK", "kr", "Swedish Krona"),
        ("CHF", "CHF", "Swiss Franc"),
        ("TRY", "₺", "Turkish Lira"),
    ]
    
    // Filter out already added currencies and apply search
    var availableCurrencies: [(code: String, symbol: String, name: String)] {
        let existingCodes = Set(existingCurrencies.map { $0.code })
        let filtered = popularCurrencies.filter { !existingCodes.contains($0.code) }
        
        if searchText.isEmpty {
            return filtered
        } else {
            return filtered.filter {
                $0.code.localizedCaseInsensitiveContains(searchText) ||
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Search currencies...", text: $searchText)
                        .textFieldStyle(.plain)
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(10)
                .padding()
                
                // Popular Currencies Section (Scrollable)
                ScrollView {
                    VStack(spacing: 12) {
                        if !availableCurrencies.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Popular Currencies")
                                    .font(.headline)
                                    .padding(.horizontal)
                                
                                ForEach(availableCurrencies, id: \.code) { curr in
                                    Button(action: {
                                        // Toggle selection
                                        if selectedCurrencies.contains(curr.code) {
                                            selectedCurrencies.remove(curr.code)
                                        } else {
                                            selectedCurrencies.insert(curr.code)
                                        }
                                    }) {
                                        HStack(spacing: 12) {
                                            Text(curr.symbol)
                                                .font(.title2)
                                                .frame(width: 60, alignment: .leading)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(curr.code)
                                                    .font(.headline)
                                                Text(curr.name)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            
                                            Spacer()
                                            
                                            Image(systemName: selectedCurrencies.contains(curr.code) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selectedCurrencies.contains(curr.code) ? .green : .gray)
                                                .font(.title3)
                                        }
                                        .padding(12)
                                        .background(Color(UIColor.systemGray6))
                                        .cornerRadius(10)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.top)
                        } else if !searchText.isEmpty {
                            Text("No currencies found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding()
                        } else {
                            Text("All popular currencies have been added")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                    }
                    .padding(.bottom, 20)
                }

                // Custom Currency Section (Fixed at bottom)
                VStack(spacing: 0) {
                    Divider()
                    
                    Button(action: {
                        withAnimation {
                            showingCustomForm.toggle()
                        }
                    }) {
                        HStack {
                            Text("Custom Currency")
                                .font(.headline)
                            
                            Spacer()
                            
                            Image(systemName: showingCustomForm ? "chevron.up" : "chevron.down")
                                .foregroundStyle(.blue)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.3)) // Darker to match disabled button
                    }
                    .buttonStyle(.plain)
                    
                    if showingCustomForm {
                        VStack(spacing: 15) {
                            TextField("Currency Code (e.g., AUD)", text: $customCode)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                            
                            TextField("Symbol (e.g., $)", text: $customSymbol)
                                .textFieldStyle(.roundedBorder)
                            
                            TextField("Full Name (e.g., Australian Dollar)", text: $customName)
                                .textFieldStyle(.roundedBorder)
                            
                            HStack {
                                Text("Exchange Rate:")
                                Spacer()
                                TextField("Rate", value: $customRate, format: .number.precision(.fractionLength(2...4)))
                                    .keyboardType(.decimalPad)
                                    .frame(width: 120)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                            }
                            
                            Button(action: addCustomCurrency) {
                                HStack {
                                    if isFetchingRate {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .tint(.white)
                                        Text("Fetching Rate...")
                                    } else {
                                        Text("Add Currency")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background((canAddCustom && !isFetchingRate) ? Color.blue : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .disabled(!canAddCustom || isFetchingRate)
                        }
                        .padding()
                        .background(Color(UIColor.systemGray5)) // Darker background for contrast
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .navigationTitle("Add Currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        addSelectedCurrencies()
                    }
                    .disabled(selectedCurrencies.isEmpty || isFetchingRate)
                }
            }
        }
    }
    
    var canAddCustom: Bool {
        !customCode.isEmpty && !customSymbol.isEmpty && !customName.isEmpty && customRate > 0
    }
    
    
    func addSelectedCurrencies() {
        // Fetch rates and add all selected currencies
        Task {
            isFetchingRate = true
            
            // Fetch latest rates from API using main currency as base
            let rates = try? await currencyService.fetchRates(base: mainCurrencyCode)
            
            await MainActor.run {
                for code in selectedCurrencies {
                    if let curr = popularCurrencies.first(where: { $0.code == code }) {
                        // Use fetched rate if available, otherwise fall back to 1.0
                        let rate = rates?[code] ?? 1.0
                        addCurrency(code: curr.code, symbol: curr.symbol, name: curr.name, rate: rate)
                    }
                }
                selectedCurrencies.removeAll()
                isFetchingRate = false
                dismiss()
            }
        }
    }
    
    func addCurrency(code: String, symbol: String, name: String, rate: Decimal) {
        let newCurrency = DraftCurrency(
            code: code,
            symbol: symbol,
            name: name,
            rate: rate,
            isMain: false,
            isEnabled: true,
            isDefault: false,
            isManual: false
        )
        onAdd(newCurrency)
    }
    
    func addCustomCurrency() {
        let code = customCode.uppercased()
        
        // Attempt to fetch rate from API if not already fetched
        if !rateAutoFetched {
            Task {
                isFetchingRate = true
                defer { isFetchingRate = false }
                
                do {
                    let rates = try await currencyService.fetchRates(base: "USD")
                    if let fetchedRate = rates[code], fetchedRate > 0 {
                        // API recognized this currency - use fetched rate
                        customRate = fetchedRate
                        rateAutoFetched = true
                        
                        // Create and add currency with auto-fetched rate
                        let newCurrency = DraftCurrency(
                            code: code,
                            symbol: customSymbol,
                            name: customName,
                            rate: fetchedRate,
                            isMain: false,
                            isEnabled: true,
                            isDefault: false,
                            isManual: false // Auto-fetched rates are not manual
                        )
                        onAdd(newCurrency)
                        dismiss()
                        return
                    }
                } catch {
                    // Failed to fetch - will use manual rate below
                    print("Failed to fetch rate for \(code): \(error)")
                }
                
                // If we get here, either API failed or code not recognized
                // Use the manually entered rate
                let newCurrency = DraftCurrency(
                    code: code,
                    symbol: customSymbol,
                    name: customName,
                    rate: customRate,
                    isMain: false,
                    isEnabled: true,
                    isDefault: false,
                    isManual: true // Manual entry
                )
                onAdd(newCurrency)
                dismiss()
            }
        } else {
            // Rate was already fetched
            let newCurrency = DraftCurrency(
                code: code,
                symbol: customSymbol,
                name: customName,
                rate: customRate,
                isMain: false,
                isEnabled: true,
                isDefault: false,
                isManual: false // Was auto-fetched
            )
            onAdd(newCurrency)
            dismiss()
        }
    }
}

struct PaymentMethodOption: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    let icon: String
    let colorHex: String // Store color as hex string for Codable
    var isEnabled: Bool
    var enabledCurrencies: Set<UUID> // Which currencies this payment method accepts
    var enabledProviders: Set<String> // Which providers this payment method accepts (e.g., "stripe")
    
    var color: Color {
        Color(hex: colorHex)
    }
    
    init(id: UUID = UUID(), name: String, icon: String, color: Color, isEnabled: Bool, enabledCurrencies: Set<UUID> = [], enabledProviders: Set<String> = []) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = color.toHex() ?? "#808080"
        self.isEnabled = isEnabled
        self.enabledCurrencies = enabledCurrencies
        self.enabledProviders = enabledProviders
    }
    
    init(id: UUID, name: String, icon: String, colorHex: String, isEnabled: Bool, enabledCurrencies: Set<UUID> = [], enabledProviders: Set<String> = []) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.isEnabled = isEnabled
        self.enabledCurrencies = enabledCurrencies
        self.enabledProviders = enabledProviders
    }
    
    static func == (lhs: PaymentMethodOption, rhs: PaymentMethodOption) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.icon == rhs.icon && lhs.colorHex == rhs.colorHex && lhs.isEnabled == rhs.isEnabled && lhs.enabledCurrencies == rhs.enabledCurrencies && lhs.enabledProviders == rhs.enabledProviders
    }
}
#Preview {
    SetupPaymentViewPreviewWrapper()
}

// Wrapper for Preview State
struct SetupPaymentViewPreviewWrapper: View {
    @State var draft: DraftEventSettings
    
    init() {
        let event = Event(name: "New Event", date: Date(), currencyCode: "EUR")
        _draft = State(initialValue: DraftEventSettings(from: event))
    }
    
    var body: some View {
        ZStack {
            Color(UIColor.systemGray6).ignoresSafeArea()
            ScrollView {
                SetupPaymentView(
                    draft: $draft,
                    bizumPhoneNumber: .constant("+34612345678"),
                    isLocked: false,
                    onRefreshRates: {}
                )
            }
        }
    }
}

// MARK: - Payment Method Configuration Sheet

struct PaymentMethodConfigSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var authService
    @Binding var method: PaymentMethodOption
    let currencies: [DraftCurrency]
    @Binding var stripeConfig: StripeConfiguration
    @Binding var bizumPhoneNumber: String
    var onSave: () -> Void
    

    @State private var localBizumPhone: String = ""
    @State private var showingBizumValidationError = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: method.icon)
                        .font(.title2)
                        .foregroundStyle(method.color)
                    
                    Text(method.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Spacer()
                }
                .padding(20)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                
                Divider()
                
                // Currencies Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("CURRENCIES")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(currencies) { currency in
                                HStack {
                                    // Currency info
                                    HStack(spacing: 8) {
                                        Text(currency.code)
                                            .font(.body)
                                            .fontWeight(.medium)
                                        
                                        Text(currency.symbol)
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    // Toggle
                                    Toggle("", isOn: Binding(
                                        get: { method.enabledCurrencies.contains(currency.id) },
                                        set: { isEnabled in
                                            if isEnabled {
                                                method.enabledCurrencies.insert(currency.id)
                                            } else {
                                                method.enabledCurrencies.remove(currency.id)
                                            }
                                        }
                                    ))
                                    .labelsHidden()
                                    .tint(.green)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                
                                if currency.id != currencies.last?.id {
                                    Divider()
                                        .padding(.leading, 20)
                                }
                            }
                        }
                    }
                }
                
                Divider()
                
                // Bizum Phone Number (only for Bizum method)
                if method.name == "Bizum" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BIZUM CONFIGURATION")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Phone Number")
                                .font(.body)
                                .fontWeight(.medium)
                            
                            HStack(spacing: 0) {
                                Text("+34")
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 8)
                                
                                TextField("Phone Number", text: $localBizumPhone)
                                    .keyboardType(.numberPad)
                                    .textContentType(.telephoneNumber)
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(8)
                            
                            if showingBizumValidationError {
                                Label("Please enter a valid 9-digit phone number", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            } else {
                                Text("Enter the 9-digit Spanish mobile number for Bizum payments")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    
                    Divider()
                }
                
                // Providers Section (only for Card and QR Code)
                if method.name == "Card" || method.name == "QR Code" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PROVIDERS")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                        
                        // Stripe Provider Toggle
                        HStack {
                            Image(systemName: "creditcard.and.123")
                                .font(.body)
                                .foregroundStyle(.blue)
                            
                            Text("Stripe")
                                .font(.body)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { method.enabledProviders.contains("stripe") },
                                set: { isEnabled in
                                    if isEnabled {
                                        method.enabledProviders.insert("stripe")
                                    } else {
                                        method.enabledProviders.remove("stripe")
                                    }
                                }
                            ))
                            .labelsHidden()
                            .tint(.blue)
                            .disabled(!stripeConfig.isEnabled || !stripeConfig.isValid)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        
                        if !stripeConfig.isEnabled || !stripeConfig.isValid {
                            Text("Configure Stripe in Providers section first")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)
                        }
                        
                        // Tap to Pay Helper (only for Card method with Stripe enabled)
                        if method.name == "Card" && stripeConfig.isEnabled && stripeConfig.isValid {
                            Divider()
                                .padding(.horizontal, 20)
                            
                            NavigationLink(destination: TapToPayEducationView(userId: authService.currentUser?.id.uuidString ?? "")) {
                                HStack {
                                    Image(systemName: "hand.tap.fill")
                                        .font(.body)
                                        .foregroundStyle(.purple)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Tap to Pay Help")
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                        
                                        Text("Learn how to accept contactless payments")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                            }
                        }
                    }
                    
                    Divider()
                }
                
                Divider()
                
                // Done button
                Button(action: {
                    // Validate Bizum phone if editing Bizum method
                    if method.name == "Bizum" {
                        let cleanedNumber = localBizumPhone.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if !cleanedNumber.isEmpty {
                            // Only validate if user entered something
                            guard cleanedNumber.count == 9, cleanedNumber.allSatisfy({ $0.isNumber }) else {
                                showingBizumValidationError = true
                                return
                            }
                            // Save with +34 prefix
                            bizumPhoneNumber = "+34" + cleanedNumber
                        } else {
                            // Clear if empty
                            bizumPhoneNumber = ""
                        }
                    }
                    
                    onSave()
                    dismiss()
                }) {
                    Text("Done")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(20)
            }
            .navigationBarHidden(true)
            .onAppear {
                // Load Bizum phone number when sheet appears
                if method.name == "Bizum" && !bizumPhoneNumber.isEmpty {
                    // Remove +34 prefix for display
                    localBizumPhone = bizumPhoneNumber.replacingOccurrences(of: "+34", with: "").trimmingCharacters(in: .whitespaces)
                }
            }

        }
    }
}
