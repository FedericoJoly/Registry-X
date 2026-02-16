import SwiftUI
import SwiftData


// Setup Section Enum
// Setup Section Enum
enum SetupSection: String, CaseIterable, Identifiable {
    case general = "General"
    case categories = "Categories"
    case products = "Products"
    case promos = "Promos"
    case payment = "Payment"
    
    var id: String { rawValue }
}

struct SetupView: View {
    @Bindable var event: Event
    
    // External Control Bindings
    @Binding var hasUnsavedChanges: Bool
    @Binding var triggerSave: Bool
    @Binding var triggerDiscard: Bool
    
    @Environment(\.dismiss) var dismiss // For 'Quit'
    @Environment(\.modelContext) var modelContext
    @Environment(AuthService.self) private var authService
    @Query private var allEvents: [Event] // For duplicate name check
    
    // Services
    @State private var currencyService = CurrencyService()
    
    // Setup Page State
    // Navigation is now handled by NavigationStack - no current section tracking needed

    
    // State for Transactional Editing
    @State private var draftSettings: DraftEventSettings?
    @State private var originalDraftSettings: DraftEventSettings? // Baseline for change detection
    @State private var originalPaymentMethods: [PaymentMethodOption] = []
    @State private var showingDiscardAlert = false

    @State private var showingExportPlaceholder = false
    @State private var showSaveConfirmation = false
    @State private var showingDuplicateNameError = false
    @State private var skipNextChangeDetection = false // Prevent false positive after save
    @State private var changeDetectionTimer: Timer?
    @State private var showingResetEventConfirmation = false
    @State private var jsonExportData: Data?
    @State private var showingJSONShare = false
    @State private var showingMergeFilePicker = false
    @State private var showingMergeSuccess = false
    @State private var mergedEventName = ""
    @State private var showingMergeDuplicateError = false
    @State private var showingMergeConfirmation = false
    @State private var pendingMergeExport: EventExport?
    @State private var xlsExportData: Data?
    @State private var showingXLSShare = false
    
    // Derived Binding (Safe Unwrapping)
    private var draftBinding: Binding<DraftEventSettings> {
        Binding(
            get: { draftSettings ?? DraftEventSettings(from: event) },
            set: { draftSettings = $0 }
        )
    }
    
    // MARK: - Export JSON
    
    private func exportJSON() {
        guard let jsonData = event.exportToJSON() else {
            print("Failed to export event to JSON")
            return
        }
        
        jsonExportData = jsonData
        showingJSONShare = true
    }
    
    // MARK: - Export XLS
    
    private func exportXLS() {
        guard let xlsData = ExcelExportService.generateExcelData(
            event: event,
            username: authService.currentUser?.username ?? "Unknown"
        ) else {
            print("Failed to export event to XLS")
            return
        }
        
        xlsExportData = xlsData
        showingXLSShare = true
    }
    
    // MARK: - Actions
    
    private func saveSettings() {
        guard let draft = draftSettings else { return }
        
        // Validation: Unique Name (excluding self), filtered by current user
        let userEvents = allEvents.filter { $0.creatorId == event.creatorId }
        if userEvents.contains(where: { $0.id != event.id && $0.name.lowercased() == draft.name.lowercased() }) {
            showingDuplicateNameError = true
            // Reset trigger if it came from external
            triggerSave = false 
            return
        }
        
        // Apply changes to Event
        event.name = draft.name
        event.currencyCode = draft.currencyCode
        event.isTotalRoundUp = draft.isTotalRoundUp
        event.areCategoriesEnabled = draft.areCategoriesEnabled
        event.arePromosEnabled = draft.arePromosEnabled
        event.defaultProductBackgroundColor = draft.defaultProductBackgroundColor
        event.ratesLastUpdated = draft.ratesLastUpdated
        event.lastModified = Date()
        
        // Sync Rates (Delete All + Re-insert Strategy for Simplicity)
        // In production with transactions, be careful not to delete history if linked.
        // But rates are per-event config.
        for rate in event.rates {
            modelContext.delete(rate)
        }
        event.rates.removeAll()
        
        for draftRate in draft.rates {
            let newRate = EventExchangeRate(currencyCode: draftRate.code, rate: draftRate.rate, isManualOverride: draftRate.isManual)
            event.rates.append(newRate)
        }
        
        // Sync Currencies (NEW MODEL)
        // First, deduplicate by code (keep first occurrence)
        var seenCodes = Set<String>()
        var deduplicatedCurrencies: [DraftCurrency] = []
        for curr in draft.currencies {
            if !seenCodes.contains(curr.code) {
                deduplicatedCurrencies.append(curr)
                seenCodes.insert(curr.code)
            }
        }
        
        let draftCurrencyIds = Set(deduplicatedCurrencies.map { $0.id })
        
        // Delete removed currencies
        let currenciesToDelete = event.currencies.filter { !draftCurrencyIds.contains($0.id) }
        for curr in currenciesToDelete {
            modelContext.delete(curr)
        }
        
        // Update or Create
        for index in deduplicatedCurrencies.indices {
            let draftCurr = deduplicatedCurrencies[index]
            
            if let existing = event.currencies.first(where: { $0.id == draftCurr.id }) {
                // Update
                existing.code = draftCurr.code
                existing.symbol = draftCurr.symbol
                existing.name = draftCurr.name
                existing.rate = draftCurr.rate
                existing.isMain = draftCurr.isMain
                existing.isEnabled = draftCurr.isEnabled
                existing.isDefault = draftCurr.isDefault
                existing.isManual = draftCurr.isManual
                existing.sortOrder = index
            } else {
                // Create
                let newCurr = Currency(
                    id: draftCurr.id,
                    code: draftCurr.code,
                    symbol: draftCurr.symbol,
                    name: draftCurr.name,
                    rate: draftCurr.rate,
                    isMain: draftCurr.isMain,
                    isEnabled: draftCurr.isEnabled,
                    isDefault: draftCurr.isDefault,
                    isManual: draftCurr.isManual,
                    sortOrder: index
                )
                event.currencies.append(newCurr)
            }
        }
        
        // Update event.currencyCode to match main currency (for backward compatibility)
        if let mainCurrency = deduplicatedCurrencies.first(where: { $0.isMain }) {
            event.currencyCode = mainCurrency.code
        }
        
        // Sync Categories
        // 1. Identify IDs in draft
        let draftIds = Set(draft.categories.map { $0.id })
        
        // 2. Delete missing (removed in draft)
        // We iterate event.categories and delete if not in draft
        // Need to be careful modifying array while iterating, better to fetch to delete
        let categoriesToDelete = event.categories.filter { !draftIds.contains($0.id) }
        for cat in categoriesToDelete {
            modelContext.delete(cat)
        }
        
        // 3. Update or Create
        for index in draft.categories.indices {
            let draftCat = draft.categories[index]
            
            if let existing = event.categories.first(where: { $0.id == draftCat.id }) {
                // Update
                existing.name = draftCat.name
                existing.hexColor = draftCat.hexColor
                existing.isEnabled = draftCat.isEnabled
                existing.sortOrder = index // Enforce index order
            } else {
                // Create
                let newCat = Category(
                    id: draftCat.id,
                    name: draftCat.name,
                    hexColor: draftCat.hexColor,
                    isEnabled: draftCat.isEnabled,
                    sortOrder: index
                )
                newCat.event = event
                modelContext.insert(newCat)
            }
        }
        
        // Sync Products
        // 1. Identify IDs in draft
        let draftProdIds = Set(draft.products.map { $0.id })
        
        // 2. Delete missing (removed in draft)
        let productsToDelete = event.products.filter { !draftProdIds.contains($0.id) }
        for prod in productsToDelete {
            modelContext.delete(prod)
        }
        
        // 3. Update or Create
        for index in draft.products.indices {
            let draftProd = draft.products[index]
            
            // Resolve Category (Must exist in DB or be created already in previous step)
            // Since we synced categories first, we can look them up in event.categories
            let linkedCategory = event.categories.first(where: { $0.id == draftProd.categoryId })
            
            if let existing = event.products.first(where: { $0.id == draftProd.id }) {
                // Update
                existing.name = draftProd.name
                existing.price = draftProd.price
                existing.category = linkedCategory
                existing.subgroup = draftProd.subgroup.isEmpty ? nil : draftProd.subgroup
                existing.isActive = draftProd.isActive
                existing.isPromo = draftProd.isPromo
                existing.sortOrder = index
            } else {
                // Create
                let newProd = Product(
                    id: draftProd.id,
                    name: draftProd.name,
                    price: draftProd.price,
                    category: linkedCategory,
                    subgroup: draftProd.subgroup.isEmpty ? nil : draftProd.subgroup,
                    isActive: draftProd.isActive,
                    isPromo: draftProd.isPromo,
                    sortOrder: index
                )
                newProd.event = event
                modelContext.insert(newProd)
            }
        }
        
        // Sync Promos
        // 1. Identify IDs in draft
        let draftPromoIds = Set(draft.promos.map { $0.id })
        
        // 2. Delete missing (removed in draft)
        let promosToDelete = event.promos.filter { !draftPromoIds.contains($0.id) }
        for promo in promosToDelete {
            modelContext.delete(promo)
        }
        
        // 3. Update or Create
        for index in draft.promos.indices {
            let draftPromo = draft.promos[index]
            
            // Resolve Category
            let linkedCategory = event.categories.first(where: { $0.id == draftPromo.categoryId })
            
            if let existing = event.promos.first(where: { $0.id == draftPromo.id }) {
                // Update
                existing.name = draftPromo.name
                existing.mode = draftPromo.mode
                existing.category = linkedCategory
                existing.maxQuantity = draftPromo.maxQuantity
                existing.tierPrices = draftPromo.tierPrices
                existing.incrementalPrice8to9 = draftPromo.incrementalPrice8to9
                existing.incrementalPrice10Plus = draftPromo.incrementalPrice10Plus
                existing.starProducts = draftPromo.starProducts
                existing.comboProducts = draftPromo.comboProducts
                existing.comboPrice = draftPromo.comboPrice
                existing.nxmN = draftPromo.nxmN
                existing.nxmM = draftPromo.nxmM
                existing.nxmProducts = draftPromo.nxmProducts
                existing.isActive = draftPromo.isActive
                existing.sortOrder = index
                existing.isDeleted = draftPromo.isDeleted
            } else {
                // Create
                let newPromo = Promo(
                    id: draftPromo.id,
                    name: draftPromo.name,
                    mode: draftPromo.mode,
                    sortOrder: index,
                    isActive: draftPromo.isActive,
                    isDeleted: draftPromo.isDeleted,
                    category: linkedCategory,
                    maxQuantity: draftPromo.maxQuantity,
                    incrementalPrice8to9: draftPromo.incrementalPrice8to9,
                    incrementalPrice10Plus: draftPromo.incrementalPrice10Plus
                )
                newPromo.tierPrices = draftPromo.tierPrices
                newPromo.starProducts = draftPromo.starProducts
                newPromo.comboProducts = draftPromo.comboProducts
                newPromo.comboPrice = draftPromo.comboPrice
                newPromo.nxmN = draftPromo.nxmN
                newPromo.nxmM = draftPromo.nxmM
                newPromo.nxmProducts = draftPromo.nxmProducts
                newPromo.event = event
                modelContext.insert(newPromo)
            }
        }
        
        // Encode and save payment methods
        if let encoded = try? JSONEncoder().encode(draft.paymentMethods) {
            event.paymentMethodsData = encoded
        }
        
        // Save Stripe configuration
        event.stripeIntegrationEnabled = draft.stripeIntegrationEnabled
        event.stripePublishableKey = draft.stripePublishableKey.isEmpty ? nil : draft.stripePublishableKey
        event.stripeBackendURL = draft.stripeBackendURL.isEmpty ? nil : draft.stripeBackendURL
        event.stripeCompanyName = draft.stripeCompanyName.isEmpty ? nil : draft.stripeCompanyName
        event.stripeLocationId = draft.stripeLocationId.isEmpty ? nil : draft.stripeLocationId
        event.bizumPhoneNumber = draft.bizumPhoneNumber.isEmpty ? nil : draft.bizumPhoneNumber
        
        // Save company information
        event.companyName = draft.companyName.isEmpty ? nil : draft.companyName
        event.fromName = draft.fromName.isEmpty ? nil : draft.fromName
        event.fromEmail = draft.fromEmail.isEmpty ? nil : draft.fromEmail
        
        // Save receipt settings
        if let encoded = try? JSONEncoder().encode(draft.receiptSettings) {
            event.receiptSettingsData = encoded
        }
        
        // Save to database FIRST
        try? modelContext.save()
        
        // THEN reset draft to match the saved state
        // BUT preserve payment methods (since Event doesn't store them)
        let currentPaymentMethods = draftSettings?.paymentMethods ?? []
        skipNextChangeDetection = true
        draftSettings = DraftEventSettings(from: event)
        draftSettings?.paymentMethods = currentPaymentMethods
        // Update original payment methods since we just saved
        originalPaymentMethods = currentPaymentMethods
        
        // Show confirmation
        withAnimation { showSaveConfirmation = true }
        
        // Reset external state
        triggerSave = false
        hasUnsavedChanges = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSaveConfirmation = false }
        }
    }
    
    private func resetEvent() {
        // Delete all transactions for this event
        let transactionsToDelete = event.transactions
        for transaction in transactionsToDelete {
            modelContext.delete(transaction)
        }
        
        // Save the changes
        try? modelContext.save()
        
        // Show confirmation (reusing same toast)
        withAnimation { showSaveConfirmation = true }
        
        // Hide after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { showSaveConfirmation = false }
        }
    }
    
    private func handleMergeFromJSON(fileURL: URL) {
        // Dismiss the file picker
        showingMergeFilePicker = false
        
        // Start accessing the security-scoped resource
        guard fileURL.startAccessingSecurityScopedResource() else {
            print("Failed to access security-scoped resource")
            return
        }
        
        defer {
            fileURL.stopAccessingSecurityScopedResource()
        }
        
        do {
            // Read JSON data
            let jsonData = try Data(contentsOf: fileURL)
            
            // Decode event export
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let eventExport = try decoder.decode(EventExport.self, from: jsonData)
            
            // Check for duplicate merge (only if eventId exists)
            if let importEventId = eventExport.eventId {
                var mergedEvents: [MergedEventIdentifier] = []
                if let data = event.mergedEventsData,
                   let decoded = try? JSONDecoder().decode([MergedEventIdentifier].self, from: data) {
                    mergedEvents = decoded
                }
                
                // Create identifier for this import
                let newIdentifier = MergedEventIdentifier(eventId: importEventId)
                
                // Check if already merged
                if mergedEvents.contains(where: { $0.eventId == newIdentifier.eventId }) {
                    // Duplicate detected - show error
                    showingMergeDuplicateError = true
                    return
                }
            }
            // Note: If eventId is nil (old export), skip duplicate detection
            
            // Store pending export and show confirmation
            pendingMergeExport = eventExport
            mergedEventName = eventExport.name
            showingMergeConfirmation = true
            
        } catch {
            print("Failed to import event: \(error.localizedDescription)")
        }
    }
    
    private func performMerge() {
        guard let eventExport = pendingMergeExport else { return }
        
        do {
            // Merge into current event
            try eventExport.mergeIntoEvent(event: event, modelContext: modelContext)
            
            // Track this merge (only if eventId exists)
            if let importEventId = eventExport.eventId {
                var mergedEvents: [MergedEventIdentifier] = []
                if let data = event.mergedEventsData,
                   let decoded = try? JSONDecoder().decode([MergedEventIdentifier].self, from: data) {
                    mergedEvents = decoded
                }
                mergedEvents.append(MergedEventIdentifier(eventId: importEventId))
                event.mergedEventsData = try? JSONEncoder().encode(mergedEvents)
            }
            
            // Save context
            try modelContext.save()
            
            // Reload draft settings to reflect merged data
            draftSettings = DraftEventSettings(from: event)
            originalPaymentMethods = draftSettings?.paymentMethods ?? []
            
            // Show success alert
            showingMergeSuccess = true
            
            // Clear pending export
            pendingMergeExport = nil
            
        } catch {
            print("Failed to merge event: \(error.localizedDescription)")
            pendingMergeExport = nil
        }
    }
    
    private func discardSettings() {
        draftSettings = DraftEventSettings(from: event)
        // Reset original payment methods to defaults
        originalPaymentMethods = draftSettings?.paymentMethods ?? []
        triggerDiscard = false
        hasUnsavedChanges = false
    }
    
    private func handleQuit() {
        if hasUnsavedChanges {
            showingDiscardAlert = true
        } else {
            dismiss()
        }
    }
    
    private func checkForChanges() {
        guard !skipNextChangeDetection else { return }
        
        if let draft = draftSettings, let original = originalDraftSettings {
            hasUnsavedChanges = (draft != original)
        }
    }
    
    // Category grid with navigation links
    private var categoryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            NavigationLink(destination: generalDetail) {
                SetupCategoryButton(title: "General", icon: "gearshape.fill", color: Color(red: 0.0, green: 0.2, blue: 0.4))
            }
            .buttonStyle(.plain)
            
            NavigationLink(destination: categoriesDetail) {
                SetupCategoryButton(title: "Categories", icon: "folder.fill", color: Color(red: 0.0, green: 0.2, blue: 0.4))
            }
            .buttonStyle(.plain)
            
            NavigationLink(destination: productsDetail) {
                SetupCategoryButton(title: "Products", icon: "cube.fill", color: Color(red: 0.0, green: 0.2, blue: 0.4))
            }
            .buttonStyle(.plain)
            
            NavigationLink(destination: companyDetail) {
                SetupCategoryButton(title: "Company", icon: "building.2.fill", color: Color(red: 0.0, green: 0.2, blue: 0.4))
            }
            .buttonStyle(.plain)
            
            if draftSettings?.arePromosEnabled == true {
                NavigationLink(destination: promosDetail) {
                    SetupCategoryButton(title: "Promos", icon: "tag.fill", color: Color(red: 0.0, green: 0.2, blue: 0.4))
                }
                .buttonStyle(.plain)
            }
            
            NavigationLink(destination: paymentDetail) {
                SetupCategoryButton(title: "Payment", icon: "dollarsign.circle.fill", color: Color(red: 0.0, green: 0.2, blue: 0.4))
            }
            .buttonStyle(.plain)
        }
    }
    
    // Detail views for each section
    private var generalDetail: some View {
        ScrollView {
            SetupGeneralView(
                draft: draftBinding,
                isLocked: event.isLocked,
                onCategoryModeChange: {
                    guard let draft = draftSettings else { return }
                    if !draft.areCategoriesEnabled {
                        for i in draftBinding.categories.wrappedValue.indices {
                            draftBinding.categories.wrappedValue[i].isEnabled = (i == 0)
                        }
                    }
                }
            )
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .navigationTitle("General")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var categoriesDetail: some View {
        SetupCategoriesView(
            categories: draftBinding.categories,
            isSingleCategoryMode: Binding(
                get: { !(draftSettings?.areCategoriesEnabled ?? true) },
                set: { _ in }
            ),
            isLocked: event.isLocked
        )
        .padding(.top, 20)
        .padding(.bottom, 20)
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var productsDetail: some View {
        SetupProductsView(
            products: draftBinding.products,
            availableCategories: draftBinding.categories.wrappedValue,
            currencyCode: draftBinding.currencyCode.wrappedValue,
            isLocked: event.isLocked
        )
        .padding(.top, 20)
        .padding(.bottom, 20)
        .id(draftBinding.products.wrappedValue.count)
        .navigationTitle("Products")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var promosDetail: some View {
        SetupPromosView(
            draft: draftBinding,
            isLocked: event.isLocked,
            onRefresh: { draftSettings?.changeId = UUID() }
        )
        .padding(.top, 20)
        .padding(.bottom, 20)
        .navigationTitle("Promos")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var paymentDetail: some View {
        ScrollView {
            SetupPaymentView(
                draft: draftBinding,
                bizumPhoneNumber: Binding(
                    get: { draftSettings?.bizumPhoneNumber ?? "" },
                    set: { newValue in
                        guard var settings = draftSettings else { return }
                        settings.bizumPhoneNumber = newValue
                        draftSettings = settings
                    }
                ),
                isLocked: event.isLocked,
                onRefreshRates: { Task { await fetchAndPopulateRates(forceOverride: true) } }
            )
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .navigationTitle("Payment")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var companyDetail: some View {
        ScrollView {
            SetupCompanyView(draft: draftBinding)
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .navigationTitle("Company")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var eventActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EVENT ACTIONS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .padding(.top, 16)
            
            // Row 1: GSheet | Reset | Save
            HStack(spacing: 12) {
                SettingsActionButton(title: "GSheet", icon: "doc.text.fill", color: Color(UIColor.systemGray5), foreground: .secondary) { showingExportPlaceholder = true }
                SettingsActionButton(title: "Reset", icon: "arrow.counterclockwise", color: .orange) { 
                    showingResetEventConfirmation = true
                }
                SettingsActionButton(title: "Save", icon: "internaldrive", color: .blue) { saveSettings() }
            }
            
            // Row 2: XLS | Merge | Export
            HStack(spacing: 12) {
                SettingsActionButton(title: "XLS", icon: "doc.text", color: .green) { exportXLS() }
                SettingsActionButton(title: "Merge", icon: "arrow.triangle.merge", color: Color(red: 0.8, green: 0.6, blue: 0.0)) { 
                    showingMergeFilePicker = true
                }
                SettingsActionButton(title: "Export", icon: "square.and.arrow.up", color: .purple) { exportJSON() }
            }
            .disabled(event.isLocked)
            .opacity(event.isLocked ? 0.6 : 1.0)
        }
        .padding(.bottom, 12)
    }
    
    private var exportActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // This section is now merged into eventActionsSection
        }
    }
    
    private var footerSection: some View {
        VStack(spacing: 0) {
            eventActionsSection
            exportActionsSection
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background(Color(UIColor.systemBackground))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: -2)
    }
    
    var body: some View {
        ZStack {
            NavigationStack {
                ZStack {
                    Color(UIColor.systemGray6).ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        // MARK: - Header (same as other tabs)
                        if let user = authService.currentUser {
                            EventInfoHeader(
                                event: event,
                                userFullName: user.fullName,
                                onQuit: { handleQuit() }
                            )
                        } else {
                            EventInfoHeader(
                                event: event,
                                userFullName: "Operator",
                                onQuit: { handleQuit() }
                            )
                        }
                        
                        // MARK: - Category Grid
                        ScrollView {
                            categoryGrid
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                        }
                        
                        // MARK: - Event Actions Footer
                        footerSection
                    }
                }
                .navigationBarHidden(true)
                .alert("Coming Soon", isPresented: $showingExportPlaceholder) { 
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("This feature will be available in a future version.")
                }
            }
            
            // Success Banner (Top) - Outside NavigationStack to stay at actual top
            if showSaveConfirmation {
                VStack {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                        Text("Settings Saved")
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
        }
        .onAppear {
            currencyService.modelContext = modelContext
            
            if draftSettings == nil {
                draftSettings = DraftEventSettings(from: event)
                // Store original payment methods for change detection
                originalPaymentMethods = draftSettings?.paymentMethods ?? []
                // Store baseline for change detection (before automatic rate fetch)
                originalDraftSettings = draftSettings
            }
            
            // Start polling timer for automatic change detection
            changeDetectionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                checkForChanges()
            }
            
            // Only auto-fetch rates for NEW events (no rates fetched yet)
            // For existing events, rates should only update when user taps Refresh
            if event.ratesLastUpdated == nil {
                Task {
                    await fetchAndPopulateRates()
                }
            }
        }
        .onDisappear {
            // Clean up timer when leaving Setup
            changeDetectionTimer?.invalidate()
            changeDetectionTimer = nil
        }
        // DISABLED: Do not auto-fetch rates when currency code changes
        // Rates should only update when creating a new event or when user clicks Refresh
        .onChange(of: draftSettings) { oldValue, newValue in
            if skipNextChangeDetection {
                skipNextChangeDetection = false
                return
            }
            
            if let new = newValue, let original = originalDraftSettings {
                hasUnsavedChanges = (new != original)
            }
        }
        .onChange(of: triggerSave) { oldValue, newValue in
            if newValue {
                saveSettings()
            }
        }
        .onChange(of: triggerDiscard) { oldValue, newValue in
            if newValue {
                discardSettings()
            }
        }
        .alert("Unsaved Changes", isPresented: $showingDiscardAlert) {
            Button("Discard Changes", role: .destructive) {
                dismiss()
            }
            Button("Save & Quit") {
                saveSettings()
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved changes in your event settings. What would you like to do?")
        }
        .alert("Name Taken", isPresented: $showingDuplicateNameError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("An event with this name already exists. Please choose another name.")
        }
        .alert("Reset Event?", isPresented: $showingResetEventConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All Transactions", role: .destructive) {
                resetEvent()
            }
        } message: {
            let count = event.transactions.count
            return Text("This will delete all \(count) transaction\(count == 1 ? "" : "s"). This action cannot be undone.")
        }
        .sheet(isPresented: $showingJSONShare) {
           if let data = jsonExportData {
                ActivityViewController(activityItems: [data], fileName: "\(event.name).json")
            }
        }
        .sheet(isPresented: $showingXLSShare) {
            if let data = xlsExportData {
                let username = authService.currentUser?.username ?? "Unknown"
                ActivityViewController(activityItems: [data], fileName: "\(event.name)_\(username).xlsx")
            }
        }
        .sheet(isPresented: $showingMergeFilePicker) {
            JSONFilePickerView(onFileSelected: { url in
                handleMergeFromJSON(fileURL: url)
            })
        }
        .alert("Event Merged", isPresented: $showingMergeSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Event '\(mergedEventName)' imported.")
        }
        .alert("Confirm Import", isPresented: $showingMergeConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingMergeExport = nil
            }
            Button("OK") {
                performMerge()
            }
        } message: {
            Text("Confirm to import '\(mergedEventName)'?")
        }
        .alert("Error", isPresented: $showingMergeDuplicateError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This event has been imported already.")
        }
    }
    
    // MARK: - Logic
    
    private func fetchAndPopulateRates(forceOverride: Bool = false) async {
        guard var draft = draftSettings else { return }
        
        // Get the main currency code
        let mainCurrencyCode = draft.currencies.first(where: { $0.isMain })?.code ?? draft.currencyCode
        
        // Fetch rates from API using main currency as base
        let fetched = try? await currencyService.fetchRates(base: mainCurrencyCode)
        
        guard let rates = fetched, !rates.isEmpty else { return }
        
        await MainActor.run {
            // Throttle Check: If not forced, and data is fresh (< 1 hour), skip updating draft
            if !forceOverride, let last = event.ratesLastUpdated, Date().timeIntervalSince(last) < 3600 {
                if !draft.rates.isEmpty {
                    return
                }
            }
            
            // Update timestamp
            draft.ratesLastUpdated = Date()
            
            // Update all non-main currencies with fetched rates
            for index in draft.currencies.indices {
                if !draft.currencies[index].isMain {
                    let code = draft.currencies[index].code
                    
                    // Skip if manual and not forcing override
                    if !forceOverride && draft.currencies[index].isManual {
                        continue
                    }
                    
                    // Use the fetched rate directly (already relative to main currency)
                    if let rate = rates[code] {
                        draft.currencies[index].rate = rate
                        if forceOverride {
                            draft.currencies[index].isManual = false
                        }
                    }
                }
            }
            
            draftSettings = draft
            
            // Update baseline after automatic rate updates (not force override)
            // This prevents false positives when rates are auto-fetched
            if !forceOverride {
                originalDraftSettings = draft
            }
        }
    }
    
    
    private func recalculateRates(newBase: String) {
        // When currency code changes, fetch new rates with the new base
        Task {
            await fetchAndPopulateRates(forceOverride: true)
        }
    }
    
    // Helpers removed - no longer needed with button grid navigation
}

// Helper Struct for Draft State
// Helper Struct for Draft State
struct DraftEventSettings: Equatable {
    var name: String
    var currencyCode: String
    var isTotalRoundUp: Bool
    var areCategoriesEnabled: Bool
    var arePromosEnabled: Bool
    var defaultProductBackgroundColor: String
    var currencies: [DraftCurrency] // NEW
    var rates: [DraftRate] // OLD - for migration compatibility
    var categories: [DraftCategory]
    var products: [DraftProduct]
    var promos: [DraftPromo]
    var paymentMethods: [PaymentMethodOption]
    var changeId: UUID = UUID() // Used to force change detection
    var ratesLastUpdated: Date?
    
    // Stripe Integration Configuration
    var stripeIntegrationEnabled: Bool
    var stripePublishableKey: String
    var stripeBackendURL: String
    var stripeCompanyName: String
    var stripeLocationId: String
    
    // Bizum Integration Configuration
    var bizumPhoneNumber: String
    
    // Company Information (for receipts)
    var companyName: String
    var fromName: String
    var fromEmail: String
    
    // Receipt Settings (per payment method)
    var receiptSettings: [String: Bool]
    
    init(from event: Event) {
        self.name = event.name
        self.currencyCode = event.currencyCode
        self.isTotalRoundUp = event.isTotalRoundUp
        self.areCategoriesEnabled = event.areCategoriesEnabled
        self.arePromosEnabled = event.arePromosEnabled
        self.defaultProductBackgroundColor = event.defaultProductBackgroundColor
        self.ratesLastUpdated = event.ratesLastUpdated
        
        // Migrate to new currencies model if needed
        if !event.currencies.isEmpty {
            // New model exists, use it
            let loadedCurrencies = event.currencies.map { DraftCurrency(from: $0) }
                .sorted { $0.sortOrder < $1.sortOrder }
            
            // DEDUPLICATE by code (keep first occurrence)
            var seenCodes = Set<String>()
            var dedupedCurrencies: [DraftCurrency] = []
            for curr in loadedCurrencies {
                if !seenCodes.contains(curr.code) {
                    dedupedCurrencies.append(curr)
                    seenCodes.insert(curr.code)
                }
            }
            
            self.currencies = dedupedCurrencies
        } else {
            // Migration: Convert old currencyCode + rates to new currencies
            var newCurrencies: [DraftCurrency] = []
            var addedCodes = Set<String>() // Track to avoid duplicates
            
            // Create main currency from event.currencyCode
            let mainCurrency = Self.createCurrencyFromCode(event.currencyCode, isMain: true, sortOrder: 0)
            newCurrencies.append(mainCurrency)
            addedCodes.insert(event.currencyCode)
            
            // Convert rates to currencies (skip if already added as main)
            for (_, rate) in event.rates.enumerated() {
                if !addedCodes.contains(rate.currencyCode) {
                    let currency = Self.createCurrencyFromCode(rate.currencyCode, isMain: false, sortOrder: newCurrencies.count)
                    var curr = currency
                    curr.rate = rate.rate
                    curr.isManual = rate.isManualOverride
                    newCurrencies.append(curr)
                    addedCodes.insert(rate.currencyCode)
                }
            }
            
            self.currencies = newCurrencies
        }
        
        // CRITICAL: Ensure at least one currency is marked as main
        // This fixes data integrity issues from migration or incomplete data
        if !self.currencies.isEmpty && !self.currencies.contains(where: { $0.isMain }) {
            // No main currency found - mark the first one or the one matching event.currencyCode as main
            if let matchingIndex = self.currencies.firstIndex(where: { $0.code == event.currencyCode }) {
                self.currencies[matchingIndex].isMain = true
            } else {
                // Fallback: mark first currency as main
                self.currencies[0].isMain = true
            }
        }
        
        // Keep old rates for backward compatibility
        self.rates = event.rates.map { DraftRate(from: $0) }
            .sorted { $0.code < $1.code }
            
        // Map Categories
        self.categories = event.categories.map { DraftCategory(from: $0) }
            .sorted { $0.sortOrder < $1.sortOrder }
            
        // Map Products
        self.products = event.products.map { DraftProduct(from: $0) }
            .sorted { $0.sortOrder < $1.sortOrder }
            
        // Map Promos
        self.promos = event.promos.map { DraftPromo(from: $0) }
            .sorted { $0.sortOrder < $1.sortOrder }
        
        // Load payment methods from Event or use defaults
        if let data = event.paymentMethodsData,
           let decoded = try? JSONDecoder().decode([PaymentMethodOption].self, from: data) {
            self.paymentMethods = decoded
            
            // Migration: Add Bizum if it doesn't exist in existing events
            if !decoded.contains(where: { $0.name == "Bizum" }) {
                self.paymentMethods.append(
                    PaymentMethodOption(name: "Bizum", icon: "phone.fill", color: Color(hex: "#00BAC1"), isEnabled: true)
                )
            }
            
            // Migration: Update Bizum color from old purple/cyan to correct logo cyan
            var migrated = false
            if let bizumIndex = self.paymentMethods.firstIndex(where: { $0.name == "Bizum" && $0.icon.contains("phone") }) {
                let old = self.paymentMethods[bizumIndex]
                let correctColor = "#00BAC1"
                if old.colorHex != correctColor {
                    self.paymentMethods[bizumIndex] = PaymentMethodOption(
                        id: old.id, name: old.name, icon: old.icon, colorHex: correctColor,
                        isEnabled: old.isEnabled, enabledCurrencies: old.enabledCurrencies, enabledProviders: old.enabledProviders
                    )
                    migrated = true
                }
            }
            
            // Save migrated color back to Event immediately
            if migrated, let updatedData = try? JSONEncoder().encode(self.paymentMethods) {
                event.paymentMethodsData = updatedData
            }
        } else {
            // Initialize default payment methods if not stored
            // Enable main currency in Cash by default
            let mainCurrencyId = self.currencies.first(where: { $0.isMain })?.id ?? UUID()
            
            self.paymentMethods = [
                PaymentMethodOption(name: "Cash", icon: "banknote", color: .green, isEnabled: true, enabledCurrencies: [mainCurrencyId]),
                PaymentMethodOption(name: "Card", icon: "creditcard", color: .blue, isEnabled: true),
                PaymentMethodOption(name: "QR Code", icon: "qrcode", color: .purple, isEnabled: true),
                PaymentMethodOption(name: "Bizum", icon: "phone.fill", color: Color(hex: "#00BAC1"), isEnabled: true, enabledCurrencies: [mainCurrencyId])
            ]
        }
        
        // Load Stripe configuration from Event
        self.stripeIntegrationEnabled = event.stripeIntegrationEnabled
        self.stripePublishableKey = event.stripePublishableKey ?? ""
        self.stripeBackendURL = event.stripeBackendURL ?? ""
        self.stripeCompanyName = event.stripeCompanyName ?? ""
        self.stripeLocationId = event.stripeLocationId ?? ""
        self.bizumPhoneNumber = event.bizumPhoneNumber ?? ""
        
        // Load company information from Event
        self.companyName = event.companyName ?? ""
        self.fromName = event.fromName ?? ""
        self.fromEmail = event.fromEmail ?? ""
        
        // Load receipt settings from Event (stored as JSON)
        if let data = event.receiptSettingsData,
           let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
            self.receiptSettings = decoded
        } else {
            self.receiptSettings = [:]
        }
    }
    
    // Helper to create currency from code with defaults
    // Helper to create currency from code with defaults
    static func createCurrencyFromCode(_ code: String, isMain: Bool, sortOrder: Int) -> DraftCurrency {
        // Default exchange rates (approximate, relative to USD as base)
        let defaults: [(code: String, symbol: String, name: String, isDefault: Bool, defaultRate: Decimal)] = [
            ("USD", "$", "US Dollar", true, 1.0),
            ("EUR", "€", "Euro", true, 0.92),
            ("GBP", "£", "British Pound", true, 0.79),
            ("JPY", "¥", "Japanese Yen", false, 149.50),
            ("CNY", "¥", "Chinese Yuan", false, 7.24),
            ("AUD", "$", "Australian Dollar", false, 1.53),
            ("CAD", "$", "Canadian Dollar", false, 1.35),
            ("CHF", "CHF", "Swiss Franc", false, 0.88),
            ("HKD", "HK$", "Hong Kong Dollar", false, 7.80),
            ("SGD", "S$", "Singapore Dollar", false, 1.34),
            ("SEK", "kr", "Swedish Krona", false, 10.35),
            ("KRW", "₩", "South Korean Won", false, 1334.50),
            ("NOK", "kr", "Norwegian Krone", false, 10.85),
            ("NZD", "$", "New Zealand Dollar", false, 1.67),
            ("INR", "₹", "Indian Rupee", false, 83.20),
            ("MXN", "$", "Mexican Peso", false, 17.05),
            ("ZAR", "R", "South African Rand", false, 18.65),
            ("BRL", "R$", "Brazilian Real", false, 5.02),
            ("RUB", "₽", "Russian Ruble", false, 91.50),
            ("TRY", "₺", "Turkish Lira", false, 32.50),
        ]
        
        if let found = defaults.first(where: { $0.code == code }) {
            return DraftCurrency(
                code: found.code,
                symbol: found.symbol,
                name: found.name,
                rate: isMain ? 1.0 : found.defaultRate,
                isMain: isMain,
                isEnabled: true,
                isDefault: found.isDefault,
                isManual: false,
                sortOrder: sortOrder
            )
        } else {
            // Unknown currency, create generic
            return DraftCurrency(
                code: code,
                symbol: code,
                name: code,
                rate: 1.0,
                isMain: isMain,
                isEnabled: true,
                isDefault: false,
                isManual: false,
                sortOrder: sortOrder
            )
        }
    }
    
    static func == (lhs: DraftEventSettings, rhs: DraftEventSettings) -> Bool {
        return lhs.name == rhs.name &&
               lhs.currencyCode == rhs.currencyCode &&
               lhs.isTotalRoundUp == rhs.isTotalRoundUp &&
               lhs.areCategoriesEnabled == rhs.areCategoriesEnabled &&
               lhs.arePromosEnabled == rhs.arePromosEnabled &&
               lhs.defaultProductBackgroundColor == rhs.defaultProductBackgroundColor &&
               lhs.currencies == rhs.currencies &&
               lhs.categories == rhs.categories &&
               lhs.products == rhs.products &&
               lhs.promos == rhs.promos &&
               lhs.paymentMethods == rhs.paymentMethods &&
               lhs.stripeIntegrationEnabled == rhs.stripeIntegrationEnabled &&
               lhs.stripePublishableKey == rhs.stripePublishableKey &&
               lhs.stripeBackendURL == rhs.stripeBackendURL &&
               lhs.stripeCompanyName == rhs.stripeCompanyName &&
               lhs.companyName == rhs.companyName &&
               lhs.fromName == rhs.fromName &&
               lhs.fromEmail == rhs.fromEmail &&
               lhs.receiptSettings == rhs.receiptSettings
               // Ignore ratesLastUpdated and changeId in dirty check
               // changeId is only used to trigger onChange, not for equality
    }
}

struct DraftRate: Identifiable {
    let id = UUID()
    var code: String
    var rate: Decimal
    var isManual: Bool
    
    init(from eventRate: EventExchangeRate) {
        self.code = eventRate.currencyCode
        self.rate = eventRate.rate
        self.isManual = eventRate.isManualOverride
    }
    
    init(code: String, rate: Decimal, isManual: Bool = false) {
        self.code = code
        self.rate = rate
        self.isManual = isManual
    }
}

extension DraftRate: Equatable {
    static func == (lhs: DraftRate, rhs: DraftRate) -> Bool {
        // If not manual, we ignore the rate value to prevent phantom alerts from background updates
        let ratesMatch = lhs.isManual ? lhs.rate == rhs.rate : true
        return lhs.code == rhs.code &&
               ratesMatch &&
               lhs.isManual == rhs.isManual
    }
}

// MARK: - Draft Currency
struct DraftCurrency: Identifiable, Equatable {
    let id: UUID
    var code: String
    var symbol: String
    var name: String
    var rate: Decimal
    var isMain: Bool
    var isEnabled: Bool
    var isDefault: Bool
    var isManual: Bool
    var sortOrder: Int
    
    init(from currency: Currency) {
        self.id = currency.id
        self.code = currency.code
        self.symbol = currency.symbol
        self.name = currency.name
        self.rate = currency.rate
        self.isMain = currency.isMain
        self.isEnabled = currency.isEnabled
        self.isDefault = currency.isDefault
        self.isManual = currency.isManual
        self.sortOrder = currency.sortOrder
    }
    
    init(id: UUID = UUID(), code: String, symbol: String, name: String, rate: Decimal = 1.0, isMain: Bool = false, isEnabled: Bool = true, isDefault: Bool = false, isManual: Bool = false, sortOrder: Int = 0) {
        self.id = id
        self.code = code
        self.symbol = symbol
        self.name = name
        self.rate = rate
        self.isMain = isMain
        self.isEnabled = isEnabled
        self.isDefault = isDefault
        self.isManual = isManual
        self.sortOrder = sortOrder
    }
    
    // Custom Equatable: Ignore automatic rate updates
    static func == (lhs: DraftCurrency, rhs: DraftCurrency) -> Bool {
        // For manual rates, compare the actual rate value
        // For automatic rates, ignore rate differences to prevent false positives from API updates
        let ratesMatch = lhs.isManual ? lhs.rate == rhs.rate : true
        
        return lhs.id == rhs.id &&
               lhs.code == rhs.code &&
               lhs.symbol == rhs.symbol &&
               lhs.name == rhs.name &&
               ratesMatch &&
               lhs.isMain == rhs.isMain &&
               lhs.isEnabled == rhs.isEnabled &&
               lhs.isDefault == rhs.isDefault &&
               lhs.isManual == rhs.isManual &&
               lhs.sortOrder == rhs.sortOrder
    }
}

// MARK: - Draft Category
struct DraftCategory: Identifiable, Equatable {
    let id: UUID // Persist ID to link back to original
    var name: String
    var hexColor: String
    var isEnabled: Bool
    var sortOrder: Int
    
    // Track state
    var isNew: Bool = false
    var isDeleted: Bool = false // Soft delete in draft, removed on save
    
    init(from category: Category) {
        self.id = category.id
        self.name = category.name
        self.hexColor = category.hexColor
        self.isEnabled = category.isEnabled
        self.sortOrder = category.sortOrder
    }
    
    init(name: String, hexColor: String, isEnabled: Bool, sortOrder: Int) {
        self.id = UUID()
        self.name = name
        self.hexColor = hexColor
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.isNew = true
    }
    
    // Custom Equatable: Exclude tracking flags from comparison
    static func == (lhs: DraftCategory, rhs: DraftCategory) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.hexColor == rhs.hexColor &&
               lhs.isEnabled == rhs.isEnabled &&
               lhs.sortOrder == rhs.sortOrder
        // Intentionally exclude isNew and isDeleted from comparison
    }
}

// MARK: - Draft Product
struct DraftProduct: Identifiable, Equatable {
    let id: UUID
    var name: String
    var price: Decimal
    var categoryId: UUID? // Link by ID for draft stability
    var subgroup: String
    var isActive: Bool
    var isPromo: Bool
    var sortOrder: Int
    
    // Track state
    var isNew: Bool = false
    
    init(from product: Product) {
        self.id = product.id
        self.name = product.name
        self.price = product.price
        self.categoryId = product.category?.id
        self.subgroup = product.subgroup ?? ""
        self.isActive = product.isActive
        self.isPromo = product.isPromo
        self.sortOrder = product.sortOrder
    }
    
    init(name: String, price: Decimal, categoryId: UUID?, subgroup: String, isActive: Bool, isPromo: Bool, sortOrder: Int) {
        self.id = UUID()
        self.name = name
        self.price = price
        self.categoryId = categoryId
        self.subgroup = subgroup
        self.isActive = isActive
        self.isPromo = isPromo
        self.sortOrder = sortOrder
        self.isNew = true
    }
    
    // Custom Equatable: Exclude tracking flags from comparison
    static func == (lhs: DraftProduct, rhs: DraftProduct) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.price == rhs.price &&
               lhs.categoryId == rhs.categoryId &&
               lhs.subgroup == rhs.subgroup &&
               lhs.isActive == rhs.isActive &&
               lhs.isPromo == rhs.isPromo &&
               lhs.sortOrder == rhs.sortOrder
        // Intentionally exclude isNew from comparison
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Event.self, configurations: config)
    let event = Event(name: "Preview Setup", date: Date(), currencyCode: "USD")
    container.mainContext.insert(event)
    
    return SetupView(
        event: event,
        hasUnsavedChanges: .constant(false),
        triggerSave: .constant(false),
        triggerDiscard: .constant(false)
    )
        .modelContainer(container)
}

// Helper for Binding Optional
extension Binding where Value: Equatable {
    func forceUnwrap<T>() -> Binding<T> where Value == T? {
        Binding<T>(
            get: { self.wrappedValue! },
            set: { self.wrappedValue = $0 }
        )
    }
}


struct SettingsActionButton: View {
    let title: String
    let icon: String
    let color: Color
    var foreground: Color = .white
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline)
            .fontWeight(.bold)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(color)
            .foregroundColor(foreground)
            .cornerRadius(10)
        }
    }
}
// MARK: - Draft Promo
struct DraftPromo: Identifiable, Equatable {
    let id: UUID
    var name: String
    var mode: PromoMode
    var categoryId: UUID? // Link by ID
    var categoryName: String? // For display
    var maxQuantity: Int
    var tierPrices: [Int: Decimal] // Tier pricing dictionary
    var incrementalPrice8to9: Decimal?
    var incrementalPrice10Plus: Decimal?
    var starProducts: [UUID: Decimal] // Product ID → extra cost
    var comboProducts: Set<UUID> = []  // Combo mode: selected products
    var comboPrice: Decimal?           // Combo mode: fixed price
    var nxmN: Int = 2                  // N x M mode: N value (items purchased)
    var nxmM: Int = 1                  // N x M mode: M value (items paid for)
    var nxmProducts: Set<UUID> = []    // N x M mode: eligible products
    var isActive: Bool
    var sortOrder: Int
    var isDeleted: Bool
    
    // Track state
    var isNew: Bool = false
    
    init(from promo: Promo) {
        self.id = promo.id
        self.name = promo.name
        self.mode = promo.mode
        self.categoryId = promo.category?.id
        self.categoryName = promo.category?.name
        self.maxQuantity = promo.maxQuantity
        self.tierPrices = promo.tierPrices
        self.incrementalPrice8to9 = promo.incrementalPrice8to9
        self.incrementalPrice10Plus = promo.incrementalPrice10Plus
        self.starProducts = promo.starProducts
        self.comboProducts = promo.comboProducts
        self.comboPrice = promo.comboPrice
        self.nxmN = promo.nxmN ?? 2
        self.nxmM = promo.nxmM ?? 1
        self.nxmProducts = promo.nxmProducts
        self.isActive = promo.isActive
        self.sortOrder = promo.sortOrder
        self.isDeleted = promo.isDeleted
    }
    
    init(name: String, mode: PromoMode = .typeList, categoryId: UUID?, categoryName: String?, maxQuantity: Int = 7, tierPrices: [Int: Decimal] = [:], incrementalPrice8to9: Decimal? = nil, incrementalPrice10Plus: Decimal? = nil, starProducts: [UUID: Decimal] = [:], comboProducts: Set<UUID> = [], comboPrice: Decimal? = nil, nxmN: Int = 2, nxmM: Int = 1, nxmProducts: Set<UUID> = [], isActive: Bool = true, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.mode = mode
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.maxQuantity = maxQuantity
        self.tierPrices = tierPrices
        self.incrementalPrice8to9 = incrementalPrice8to9
        self.incrementalPrice10Plus = incrementalPrice10Plus
        self.starProducts = starProducts
        self.comboProducts = comboProducts
        self.comboPrice = comboPrice
        self.nxmN = nxmN
        self.nxmM = nxmM
        self.nxmProducts = nxmProducts
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.isDeleted = false
        self.isNew = true
    }
    
    static func == (lhs: DraftPromo, rhs: DraftPromo) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.mode == rhs.mode &&
               lhs.categoryId == rhs.categoryId &&
               lhs.maxQuantity == rhs.maxQuantity &&
               lhs.tierPrices == rhs.tierPrices &&
               lhs.incrementalPrice8to9 == rhs.incrementalPrice8to9 &&
               lhs.incrementalPrice10Plus == rhs.incrementalPrice10Plus &&
               lhs.starProducts == rhs.starProducts &&
               lhs.comboProducts == rhs.comboProducts &&
               lhs.comboPrice == rhs.comboPrice &&
               lhs.nxmN == rhs.nxmN &&
               lhs.nxmM == rhs.nxmM &&
               lhs.nxmProducts == rhs.nxmProducts &&
               lhs.isActive == rhs.isActive &&
               lhs.sortOrder == rhs.sortOrder &&
               lhs.isDeleted == rhs.isDeleted
        // Intentionally exclude isNew from comparison
    }
}

// MARK: - Merged Event Identifier

struct MergedEventIdentifier: Codable {
    let eventId: UUID
}

// MARK: - Setup Category Button Component

struct SetupCategoryButton: View {
    let title: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.white)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 110)
        .background(color)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}
