import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct EventListView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var easterEgg = EasterEggManager.shared
    // Query removed in favor of FilteredEventList

    
    @State private var showingCreateEvent = false
    @State private var showingLoadEvent = false
    @State private var loadedEvent: Event?
    @State private var navigateToLoadedEvent = false
    @State private var showingUserManagement = false
    @State private var userToEdit: User?
    
    // ACTION STATES
    @State private var eventToDelete: Event?
    @State private var showingDeleteAlert = false
    @State private var deletePin = ""
    @State private var deleteError = false
    
    @State private var eventToDuplicate: Event?
    @State private var showingDuplicateAlert = false
    @State private var duplicateName = ""
    
    @State private var eventToLock: Event?
    @State private var showingLockAlert = false
    @State private var lockPin = ""
    @State private var showingPinError = false
    @State private var pinErrorMessage = ""
    
    @State private var eventToUnlock: Event?
    @State private var showingUnlockAlert = false
    @State private var unlockPin = ""
    @State private var unlockError = false
    @State private var showingDuplicateError = false
    
    @State private var showingImportPicker = false
    @State private var importError: String?
    @State private var showingBackupShare = false
    @State private var backupFolderURL: URL?
    @State private var isBackingUp = false
    
    // Notification banner
    @State private var showNotificationBanner = false
    @State private var notificationMessage = ""
    @State private var notificationColor: Color = .green
    
    var body: some View {
                // MARK: - Navigation Stack (Wraps Body Content Only)
                NavigationStack {
                    ZStack {
                        // GLOBAL BACKGROUND: The ultimate source of Gray
                        Color(UIColor.systemGray6).ignoresSafeArea()
                        
                        VStack(spacing: 0) {
                            // MARK: - Header
                            HStack {
                                // Left Side Content
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("REGISTRY X")
                                        .font(.custom("Atmospheric", size: 28))
                                        .fontWeight(.black)
                                        .textCase(.uppercase)
                                        .tracking(1)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .overlay(alignment: .trailing) {
                                            // Easter egg tap area on "X"
                                            Color.clear
                                                .frame(width: 30, height: 40)
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    easterEgg.handleTap()
                                                }
                                        }
                                    
                                    Text("Version 2.0 (2026.2)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.bottom, 5)
                                    
                                    Text("Welcome \(authService.currentUser?.fullName ?? "User")!")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.trailing, 60)
                                .overlay(alignment: .trailing) {
                                    // Right Side Actions
                                    VStack {
                                        Button(action: { authService.logout() }) {
                                            Image(systemName: "door.left.hand.open")
                                                .font(.system(size: 20))
                                                .foregroundStyle(.red)
                                                .frame(width: 44, height: 44)
                                                .offset(y: 2)
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: { 
                                            userToEdit = authService.currentUser
                                        }) {
                                            Image(systemName: "person.circle")
                                                .font(.system(size: 26))
                                                .foregroundStyle(.blue)
                                                .frame(width: 44, height: 44)
                                                .offset(y: 1)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 24)
                            .background(Color(UIColor.systemBackground).shadow(color: .black.opacity(0.05), radius: 4, y: 2)) // Adaptive Background for Header
                            
                            VStack(spacing: 0) {
                                // MARK: - Event Actions
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("EVENT MANAGER")
                                        .font(.headline)
                                        .padding(.horizontal, 24)
                                    
                                    VStack(spacing: 12) {
                                        // Row 1: Load | Create
                                        HStack(spacing: 12) {
                                            // Load Event
                                            Button(action: { showingLoadEvent = true }) {
                                                VStack(spacing: 4) {
                                                    Image(systemName: "folder")
                                                        .font(.title2)
                                                    Text("Load")
                                                        .font(.headline)
                                                        .fontWeight(.semibold)
                                                    Text("Open existing event")
                                                        .font(.caption)
                                                        .opacity(0.9)
                                                }
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 90)
                                                .background(Color.orange)
                                                .foregroundColor(.white)
                                                .cornerRadius(16)
                                            }
                                            
                                            // Create New Event
                                            Button(action: { showingCreateEvent = true }) {
                                                VStack(spacing: 4) {
                                                    Image(systemName: "plus")
                                                        .font(.title2)
                                                    Text("Create")
                                                        .font(.headline)
                                                        .fontWeight(.semibold)
                                                    Text("Start from scratch")
                                                        .font(.caption)
                                                        .opacity(0.9)
                                                }
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 90)
                                                .background(Color.blue)
                                                .foregroundColor(.white)
                                                .cornerRadius(16)
                                            }
                                        }
                                        
                                        // Row 2: Backup | Import
                                        HStack(spacing: 12) {
                                             // Backup All Events
                                            ZStack {
                                                VStack(spacing: 4) {
                                                    if isBackingUp {
                                                        ProgressView()
                                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                            .scaleEffect(1.5)
                                                            .padding(.vertical, 4)
                                                    } else {
                                                        Image(systemName: "doc.on.doc")
                                                            .font(.title2)
                                                    }
                                                    Text(isBackingUp ? "Preparing files..." : "Backup")
                                                        .font(.headline)
                                                        .fontWeight(.semibold)
                                                    if !isBackingUp {
                                                        Text("Export all events")
                                                            .font(.caption)
                                                            .opacity(0.9)
                                                    }
                                                }
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 90)
                                                .background(Color.green)
                                                .foregroundColor(.white)
                                                .cornerRadius(16)
                                            }
                                            .onTapGesture {
                                                guard !isBackingUp else { return }
                                                Task { await backupAllEvents() }
                                            }
                                            
                                            // Import Event
                                            Button(action: { showingImportPicker = true }) {
                                                VStack(spacing: 4) {
                                                    Image(systemName: "square.and.arrow.down")
                                                        .font(.title2)
                                                    Text("Import")
                                                        .font(.headline)
                                                        .fontWeight(.semibold)
                                                    Text("From JSON file")
                                                        .font(.caption)
                                                        .opacity(0.9)
                                                }
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 90)
                                                .background(Color.purple)
                                                .foregroundColor(.white)
                                                .cornerRadius(16)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 24)
                                }
                                .padding(.vertical, 20)
                                
                                // MARK: - Recent Events List
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text("Recent Events")
                                            .font(.headline)
                                        EventCountLabel(userId: authService.currentUser?.id)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 24)
                                    
                                    FilteredEventList(
                                        userId: authService.currentUser?.id,
                                        onDuplicate: { event in
                                            eventToDuplicate = event
                                            duplicateName = "\(event.name) Copy"
                                            showingDuplicateAlert = true
                                        },
                                        onLockStateChange: { event in
                                            if event.isLocked {
                                                eventToUnlock = event
                                                unlockPin = ""
                                                showingUnlockAlert = true
                                            } else {
                                                eventToLock = event
                                                lockPin = ""
                                                showingLockAlert = true
                                            }
                                        },
                                        onDelete: { event in
                                            eventToDelete = event
                                            deletePin = ""
                                            showingDeleteAlert = true
                                        }
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        
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
                    .background(Color(UIColor.systemGray6)) // Critical: Ensures nav stack background is gray
                    .toolbar(.hidden, for: .navigationBar) // Clean Nav Bar
               // MARK: - Modals
        .sheet(isPresented: $showingCreateEvent) {
            CreateEventView()
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingLoadEvent) {
            LoadEventView(userId: authService.currentUser?.id) { event in
                loadedEvent = event
                // Small delay to allow sheet to dismiss before navigating?
                // Usually better to set flag after dismiss, but let's try direct.
                // NavigationDestination(isPresented) works well.
                navigateToLoadedEvent = true
            }
        }
        .sheet(isPresented: $showingUserManagement) {
            UsersManagementView()
        }
        .sheet(isPresented: $showingBackupShare) {
            if let folderURL = backupFolderURL {
                ActivityViewController(activityItems: [folderURL], onComplete: {
                    showingBackupShare = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showActionNotification("Backup Successful", color: .green)
                    }
                })
                    .onDisappear {
                        // Clean up temp folder when share sheet dismisses
                        isBackingUp = false
                        try? FileManager.default.removeItem(at: folderURL)
                        backupFolderURL = nil
                    }
            }
        }
        .navigationDestination(isPresented: $navigateToLoadedEvent) {
            if let event = loadedEvent {
                EventDashboardView(event: event)
            }
        }    // Edit Current User
            .sheet(item: $userToEdit) { user in
                UserFormView(userToEdit: user)
                    .presentationDetents([.fraction(0.85)])
                    .presentationCornerRadius(20)
            }
            
    // DUPLICATE ALERT
    .alert("Duplicate Event", isPresented: $showingDuplicateAlert) {
        TextField("New Name", text: $duplicateName)
        Button("Duplicate") {
            if let original = eventToDuplicate {
                validateAndDuplicate(original, newName: duplicateName)
            }
        }
        Button("Cancel", role: .cancel) { }
    } message: {
        Text("Enter a name for the new copy.")
    }
    
    // LOCK SHEET
    .sheet(isPresented: $showingLockAlert) {
        PINEntryView(
            title: "Lock Event",
            message: "Set a 6-digit PIN code to lock this event.",
            onSubmit: { enteredPin in
                if enteredPin.count != 6 { return "PIN must be exactly 6 digits." }
                if !enteredPin.allSatisfy({ $0.isNumber }) { return "PIN must contain only numbers." }
                if let target = eventToLock {
                    target.pinCode = enteredPin
                    target.isLocked = true
                }
                lockPin = ""
                return nil
            },
            onCancel: { lockPin = "" }
        )
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }
    
    .sheet(isPresented: $showingUnlockAlert) {
        PINEntryView(
            title: "Unlock Event",
            message: "Enter the PIN to unlock.",
            onSubmit: { enteredPin in
                if let target = eventToUnlock, target.pinCode == enteredPin {
                    target.isLocked = false
                    target.pinCode = nil
                    unlockPin = ""
                    return nil
                }
                return "Incorrect PIN. Try again."
            },
            onCancel: { unlockPin = "" }
        )
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }
    
    // DELETE ALERT (Protected)
    .alert("Delete Event?", isPresented: $showingDeleteAlert) {
        if let target = eventToDelete, target.isLocked {
            SecureField("Enter PIN to confirm", text: $deletePin)
                .keyboardType(.numberPad)
        }
        Button("Delete", role: .destructive) {
            if let target = eventToDelete {
                if target.isLocked {
                    if target.pinCode == deletePin {
                        modelContext.delete(target)
                    } else {
                        // WRONG PIN
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                        deleteError = true
                    }
                } else {
                    modelContext.delete(target)
                }
            }
        }
        Button("Cancel", role: .cancel) { }
    } message: {
        if let target = eventToDelete, target.isLocked {
            Text("This event is LOCKED. Enter PIN to delete.")
        } else {
            Text("Are you sure you want to delete '\(eventToDelete?.name ?? "")'? This cannot be undone.")
        }
    }
    // DELETE ERROR
    .alert("Incorrect PIN", isPresented: $deleteError) {
        Button("OK", role: .cancel) {}
    } message: {
        Text("The PIN you entered is incorrect. Deletion cancelled.")
    }
    
    // PIN VALIDATION ERROR
    .alert("Invalid PIN", isPresented: $showingPinError) {
        Button("OK", role: .cancel) {}
    } message: {
        Text(pinErrorMessage)
    }
    // Secondary Duplicate Error Alert
     .alert("Name Taken", isPresented: $showingDuplicateError) {
        Button("OK", role: .cancel) { }
    } message: {
         Text("An event with that name already exists.")
     }
    // Import Error Alert
    .alert("Import Failed", isPresented: .init(
        get: { importError != nil },
        set: { if !$0 { importError = nil } }
    )) {
        Button("OK", role: .cancel) { }
    } message: {
        Text(importError ?? "Unknown error")
    }
    // File Import Picker
    .fileImporter(
        isPresented: $showingImportPicker,
        allowedContentTypes: [.json],
        allowsMultipleSelection: false
    ) { result in
        handleImport(result: result)
    }
    .overlay {
        if showNotificationBanner {
            VStack {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                    Text(notificationMessage)
                        .foregroundStyle(.white)
                        .font(.subheadline)
                        .bold()
                    Spacer()
                }
                .padding()
                .background(notificationColor)
                .cornerRadius(12)
                .shadow(radius: 5)
                .padding(.horizontal)
                .padding(.top, 60)
                
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(999)
        }
    }

    } // body
    }
    
    // MARK: - Logic Helpers
    
    
    private func validateAndDuplicate(_ original: Event, newName: String) {
        do {
            let descriptor = FetchDescriptor<Event>()
            let allEvents = try modelContext.fetch(descriptor)
            let userEvents = allEvents.filter { $0.creatorId == authService.currentUser?.id }
            
            if userEvents.contains(where: { $0.name.lowercased() == newName.lowercased() }) {
                showingDuplicateError = true
            } else {
                duplicateEvent(original, newName: newName)
            }
        } catch {
            print("Error checking duplicates: \(error)")
        }
    }
    
    private func duplicateEvent(_ original: Event, newName: String) {
        // Create new event with all settings from original
        let newEvent = Event(
            name: newName,
            date: Date(),
            isLocked: false, 
            pinCode: nil,
            currencyCode: original.currencyCode,
            isTotalRoundUp: original.isTotalRoundUp,
            areCategoriesEnabled: original.areCategoriesEnabled,
            arePromosEnabled: original.arePromosEnabled,
            defaultProductBackgroundColor: original.defaultProductBackgroundColor,
            creatorName: authService.currentUser?.username ?? "Unknown",
            creatorId: authService.currentUser?.id,
            ratesLastUpdated: original.ratesLastUpdated,
            stripeBackendURL: original.stripeBackendURL,
            stripePublishableKey: original.stripePublishableKey,
            stripeCompanyName: original.stripeCompanyName,
            stripeLocationId: original.stripeLocationId,
            bizumPhoneNumber: original.bizumPhoneNumber,
            receiptSettingsData: original.receiptSettingsData
        )
        
        // Copy company email configuration
        newEvent.companyName = original.companyName
        newEvent.fromName = original.fromName
        newEvent.fromEmail = original.fromEmail
        
        // NOTE: closingDate is intentionally NOT copied — a duplicate should not
        // inherit the auto-finalise schedule of the original event.
        
        // Copy Stripe integration enabled flag
        newEvent.stripeIntegrationEnabled = original.stripeIntegrationEnabled
        
        // Copy stock control settings
        newEvent.isStockControlEnabled = original.isStockControlEnabled
        
        // Save first to get ID
        modelContext.insert(newEvent)
        
        // Copy OLD Rates (for backward compatibility)
        for rate in original.rates {
            let newRate = EventExchangeRate(currencyCode: rate.currencyCode, rate: rate.rate, isManualOverride: rate.isManualOverride)
            newRate.event = newEvent
            modelContext.insert(newRate)
        }
        
        // Copy NEW Currencies model
        for currency in original.currencies {
            let newCurrency = Currency(
                code: currency.code,
                symbol: currency.symbol,
                name: currency.name,
                rate: currency.rate,
                isMain: currency.isMain,
                isEnabled: currency.isEnabled,
                isDefault: currency.isDefault,
                isManual: currency.isManual,
                sortOrder: currency.sortOrder
            )
            newCurrency.event = newEvent
            modelContext.insert(newCurrency)
        }
        
        // Copy Categories first (needed for product relationships)
        // Map old category IDs to new ones
        var categoryIdMap: [UUID: Category] = [:]
        for cat in original.categories {
            let newCat = Category(
                name: cat.name,
                hexColor: cat.hexColor,
                isEnabled: cat.isEnabled,
                sortOrder: cat.sortOrder
            )
            newCat.event = newEvent
            modelContext.insert(newCat)
            categoryIdMap[cat.id] = newCat
        }
        
        
        // Copy Products with all properties (filter out deleted products)
        for prod in original.products.filter({ !$0.isDeleted }) {
            // Map category relationship
            let linkedCategory = prod.category != nil ? categoryIdMap[prod.category!.id] : nil
            
            let newProd = Product(
                name: prod.name,
                price: prod.price,
                category: linkedCategory,
                subgroup: prod.subgroup,
                isActive: prod.isActive,
                isPromo: prod.isPromo,
                sortOrder: prod.sortOrder
            )
            newProd.stockQty = prod.stockQty
            newProd.event = newEvent
            modelContext.insert(newProd)
        }
        
        // Copy Promos with proper category and product references
        var productIdMap: [UUID: Product] = [:]
        // Build product map for promo references (only non-deleted products)
        let activeProducts = original.products.filter({ !$0.isDeleted })
        for (index, prod) in activeProducts.enumerated() {
            productIdMap[prod.id] = newEvent.products[index]
        }
        
        for promo in original.promos {
            let newPromo = Promo(
                name: promo.name,
                mode: promo.mode,
                sortOrder: promo.sortOrder,
                isActive: promo.isActive,
                isDeleted: promo.isDeleted,
                category: promo.category != nil ? categoryIdMap[promo.category!.id] : nil,
                maxQuantity: promo.maxQuantity,
                incrementalPrice8to9: promo.incrementalPrice8to9,
                incrementalPrice10Plus: promo.incrementalPrice10Plus
            )
            
            // Copy tier prices
            var newTierPrices: [Int: Decimal] = [:]
            for (qty, price) in promo.tierPrices {
                newTierPrices[qty] = price
            }
            newPromo.tierPrices = newTierPrices
            
            // Copy star products (map to new product IDs with surcharges)
            var newStarProducts: [UUID: Decimal] = [:]
            for (oldId, surcharge) in promo.starProducts {
                if let newProductId = productIdMap[oldId]?.id {
                    newStarProducts[newProductId] = surcharge
                }
            }
            newPromo.starProducts = newStarProducts
            
            // Copy combo products (map to new product IDs)
            var newComboProducts: Set<UUID> = []
            for oldId in promo.comboProducts {
                if let newProductId = productIdMap[oldId]?.id {
                    newComboProducts.insert(newProductId)
                }
            }
            newPromo.comboProducts = newComboProducts
            newPromo.comboPrice = promo.comboPrice
            
            // Copy N x M products (map to new product IDs)
            var newNxMProducts: Set<UUID> = []
            for oldId in promo.nxmProducts {
                if let newProductId = productIdMap[oldId]?.id {
                    newNxMProducts.insert(newProductId)
                }
            }
            newPromo.nxmProducts = newNxMProducts
            newPromo.nxmN = promo.nxmN
            newPromo.nxmM = promo.nxmM
            
            // Copy discount properties (map product IDs)
            newPromo.discountValue = promo.discountValue
            newPromo.discountType = promo.discountType
            newPromo.discountTarget = promo.discountTarget
            if let oldIds = try? JSONDecoder().decode(Set<UUID>.self, from: promo.discountProductIds ?? Data()) {
                let newIds = Set(oldIds.compactMap { productIdMap[$0]?.id })
                newPromo.discountProductIds = try? JSONEncoder().encode(newIds)
            }
            
            newPromo.event = newEvent
            modelContext.insert(newPromo)
        }
        
        // Copy Payment Methods with currency ID remapping
        var currencyIdMap: [UUID: UUID] = [:]
        for (index, curr) in original.currencies.enumerated() {
            currencyIdMap[curr.id] = newEvent.currencies[index].id
        }
        
        if let paymentData = original.paymentMethodsData,
           let paymentMethods = try? JSONDecoder().decode([PaymentMethodOption].self, from: paymentData) {
            // Remap currency IDs
            var remappedMethods: [PaymentMethodOption] = []
            for method in paymentMethods {
                var remappedCurrencies: Set<UUID> = []
                for oldCurrId in method.enabledCurrencies {
                    if let newCurrId = currencyIdMap[oldCurrId] {
                        remappedCurrencies.insert(newCurrId)
                    }
                }
                
                let newMethod = PaymentMethodOption(
                    id: method.id, // Keep same ID for consistency
                    name: method.name,
                    icon: method.icon,
                    colorHex: method.colorHex,
                    isEnabled: method.isEnabled,
                    enabledCurrencies: remappedCurrencies,
                    enabledProviders: method.enabledProviders
                )
                remappedMethods.append(newMethod)
            }
            
            newEvent.paymentMethodsData = try? JSONEncoder().encode(remappedMethods)
        }
        
        // Copy Transactions
        for trans in original.transactions {
             let newTrans = Transaction(timestamp: trans.timestamp, totalAmount: trans.totalAmount, currencyCode: trans.currencyCode, note: trans.note, paymentMethod: trans.paymentMethod)
             newTrans.event = newEvent
             modelContext.insert(newTrans)
              for item in trans.lineItems {
                  let newItem = LineItem(productName: item.productName, quantity: item.quantity, unitPrice: item.unitPrice, subgroup: item.subgroup)
                  // Link to new product by productName (avoid accessing invalidated product relationship)
                  if let newProduct = newEvent.products.first(where: { $0.name == item.productName }) {
                      newItem.product = newProduct
                  }
                 newTrans.lineItems.append(newItem)
                 modelContext.insert(newItem)
             }
        }
    }
    
    @MainActor
    private func backupAllEvents() async {

        
        // Set loading state
        isBackingUp = true
        
        // Fetch all events
        let descriptor = FetchDescriptor<Event>()
        guard let allEvents = try? modelContext.fetch(descriptor) else {
            isBackingUp = false
            importError = "Failed to fetch events for backup"
            return
        }
        
        guard !allEvents.isEmpty else {
            isBackingUp = false
            importError = "No events to backup"
            return
        }
        

        
        // Create timestamped folder name
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let timestamp = formatter.string(from: Date())
        let folderName = "Registry_X_BKP_\(timestamp)"
        
        // Create temp directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(folderName)
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            var usedNames: Set<String> = []
            
            // Export each event to JSON file
            for event in allEvents {
                guard let jsonData = event.exportToJSON() else {
                    continue
                }
                
                // Sanitize filename
                let sanitizedName = event.name
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ":", with: "-")
                    .replacingOccurrences(of: "\\", with: "-")
                
                // Handle duplicate names
                var fileName = "\(sanitizedName).json"
                var counter = 1
                while usedNames.contains(fileName) {
                    fileName = "\(sanitizedName)_\(counter).json"
                    counter += 1
                }
                usedNames.insert(fileName)
                
                // Write JSON file
                let fileURL = tempDir.appendingPathComponent(fileName)
                try jsonData.write(to: fileURL)
            }
            

            // Update UI
            backupFolderURL = tempDir
            showingBackupShare = true
            
        } catch {
            isBackingUp = false
            importError = "Failed to create backup: \(error.localizedDescription)"
        }
    }
    
    private func showActionNotification(_ message: String, color: Color) {
        notificationMessage = message
        notificationColor = color
        withAnimation { showNotificationBanner = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showNotificationBanner = false }
        }
    }
    
    private func handleImport(result: Result<[URL], Error>) {
        do {
            guard let selectedFile = try result.get().first else {
                importError = "No file selected"
                return
            }
            
            // Start accessing security-scoped resource
            guard selectedFile.startAccessingSecurityScopedResource() else {
                importError = "Cannot access file"
                return
            }
            defer { selectedFile.stopAccessingSecurityScopedResource() }
            
            // Read file data
            let data = try Data(contentsOf: selectedFile)
            
            // Decode JSON
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let eventExport = try decoder.decode(EventExport.self, from: data)
            
            // Create event from export
            guard let newEvent = eventExport.createEvent(
                modelContext: modelContext,
                userId: authService.currentUser?.id,
                username: authService.currentUser?.username
            ) else {
                importError = "Failed to create event from import"
return
            }
            
            showActionNotification("'\(newEvent.name)' Imported", color: .purple)
            
        } catch let decodingError as DecodingError {
            importError = "Invalid JSON format: \(decodingError.localizedDescription)"
        } catch {
            importError = "Import failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Event Card Component
struct EventCard: View {
    let event: Event
    let onDuplicate: () -> Void
    let onLockStateChange: () -> Void
    let onDelete: () -> Void
    
    @State private var isRenaming = false
    @State private var editedName = ""
    @FocusState private var isFocused: Bool
    @Environment(\.modelContext) private var viewContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // Conditional Interaction:
            // If Renaming: Show TextField (No Navigation)
            // If Not: Show NavigationLink
            Group {
                if isRenaming {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                             TextField("Event Name", text: $editedName)
                                .font(.title3)
                                .bold()
                                .textFieldStyle(.roundedBorder) // Make it obvious it's editable
                                .focused($isFocused)
                                .onSubmit {
                                    if !editedName.isEmpty {
                                        event.name = editedName
                                        try? viewContext.save()
                                    }
                                    isRenaming = false
                                }
                                .submitLabel(.done)
                            
                            Text("\(event.creatorName) • \(event.date.formatted(date: .numeric, time: .omitted))")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .opacity(0.5) // Dim other info while editing
                        }
                        Spacer()
                    }
                    .padding()
                } else {
                    NavigationLink(destination: EventDashboardView(event: event)) {
                        HStack(alignment: .top) {
                             VStack(alignment: .leading, spacing: 4) {
                                Text(event.name)
                                    .font(.title3)
                                    .bold()
                                    .foregroundStyle(.primary)
                                
                                Text("Modified: \(event.lastModified.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    
                                if event.isLocked, let pin = event.pinCode {
                                    Text("PIN: \(pin)")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(event.isFinalised ? Color(red: 0.5, green: 0.0, blue: 0.13) : Color.indigo)
                                        .cornerRadius(6)
                                        .padding(.top, 2)
                                }
                            }
                            
                            Spacer()
                            
                            Text("ID\n\(event.id.uuidString.prefix(8))")
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .padding(6)
                                .background(Color(UIColor.systemGray6))
                                .cornerRadius(6)
                        }
                        .padding()
                        .contentShape(Rectangle()) // Make entire area tappable
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Divider()
            
            // Action Bar
            HStack(spacing: 15) {
                Spacer()
                
                // RENAME
                ActionButton(icon: isRenaming ? "checkmark" : "pencil", color: Color(red: 0, green: 0.5, blue: 0)) {
                    if isRenaming {
                        // Save
                        if !editedName.isEmpty {
                            event.name = editedName
                        }
                        isRenaming = false
                    } else {
                        // Start Renaming
                        editedName = event.name
                        isRenaming = true
                        isFocused = true
                    }
                }
                .disabled(event.isLocked)
                
                // DUPLICATE
                ActionButton(icon: "doc.on.doc", color: .blue) {
                    onDuplicate()
                }
                
                // LOCK/UNLOCK
                ActionButton(icon: event.isLocked ? "lock.open" : "lock.fill", color: .orange) {
                    onLockStateChange()
                }
                .disabled(event.isFinalised)
                .opacity(event.isFinalised ? 0.4 : 1.0)
                
                // DELETE
                ActionButton(icon: "trash", color: .red) {
                    onDelete()
                }
            }
            .padding(10)
            .background(Color(UIColor.systemGray6).opacity(0.3))
        }
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct ActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(color.opacity(0.5), lineWidth: 1.5)
                )
        }
    }
}

#Preview {
    EventListView()
        .environment(AuthService())
}
