import SwiftUI
import SwiftData

struct SetupPromosView: View {
    @Binding var draft: DraftEventSettings
    var isLocked: Bool
    var onRefresh: () -> Void
    
    // Sheet State
    @State private var showingAddSheet = false
    @State private var editingPromo: DraftPromo? // If set, showing edit sheet
    
    // Deletion State
    @State private var showingDeleteAlert = false
    @State private var promoIdToDelete: UUID?
    
    var activePromos: [DraftPromo] {
        draft.promos.filter { !$0.isDeleted }.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                
                // MARK: - Header Actions
                HStack(alignment: .center) {
                    if !activePromos.isEmpty {
                        Text("Tap a promo to edit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Spacer()
                    }
                    
                    Spacer()
                    
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.blue)
                    }
                    .disabled(isLocked)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(UIColor.systemGray6))
                
                // MARK: - Promo List
                if activePromos.isEmpty {
                    ContentUnavailableView("No Promos", systemImage: "gift", description: Text("Add promos to create volume discounts."))
                        .padding(.top, 40)
                        .background(Color(UIColor.systemGray6))
                } else {
                    List {
                        ForEach(activePromos) { promo in
                            PromoRow(
                                promo: promo,
                                draft: $draft,
                                currencySymbol: currencySymbol,
                                isLocked: isLocked,
                                onTap: {
                                    if !isLocked {
                                        editingPromo = promo
                                    }
                                },
                                onDelete: {
                                    promoIdToDelete = promo.id
                                    showingDeleteAlert = true
                                }
                            )
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .background(Color(UIColor.systemGray6))
        
        // MARK: - Sheets
        
        // 1. ADD NEW
        .sheet(isPresented: $showingAddSheet) {
            PromoFormSheet(
                title: "Add New Promo",
                promo: nil,
                availableCategories: draft.categories.filter { !$0.isDeleted },
                availableProducts: draft.products,
                currencyCode: draft.currencyCode,
                currencySymbol: currencySymbol,
                onSave: { new in
                    addPromo(new)
                    showingAddSheet = false
                },
                onCancel: { showingAddSheet = false }
            )
            .presentationDetents([.large])
            .presentationCornerRadius(20)
        }
        
        // 2. EDIT
        .sheet(item: $editingPromo) { promoToEdit in
            PromoFormSheet(
                title: "Edit Promo",
                promo: promoToEdit,
                availableCategories: draft.categories.filter { !$0.isDeleted },
                availableProducts: draft.products,
                currencyCode: draft.currencyCode,
                currencySymbol: currencySymbol,
                onSave: { updated in
                    updatePromo(updated)
                    editingPromo = nil
                },
                onCancel: { editingPromo = nil }
            )
            .presentationDetents([.large])
            .presentationCornerRadius(20)
        }
        
        // MARK: - Alerts
        .alert("Delete Promo?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let id = promoIdToDelete {
                    deletePromo(id: id)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this promo?")
        }
    }
    
    // MARK: - Logic
    
    private var currencySymbol: String {
        draft.currencies.first(where: { $0.code == draft.currencyCode })?.symbol ?? draft.currencyCode
    }
    
    private func addPromo(_ new: DraftPromo) {
        var promo = new
        // Auto-assign order
        promo.sortOrder = (draft.promos.map { $0.sortOrder }.max() ?? -1) + 1
        draft.promos.append(promo)
        onRefresh()
    }
    
    private func updatePromo(_ updated: DraftPromo) {
        if let idx = draft.promos.firstIndex(where: { $0.id == updated.id }) {
            draft.promos[idx] = updated
            onRefresh()
        }
    }
    
    private func deletePromo(id: UUID) {
        draft.promos.removeAll { $0.id == id }
        onRefresh()
    }
}

// MARK: - Promo Row Component
struct PromoRow: View {
    let promo: DraftPromo
    @Binding var draft: DraftEventSettings
    let currencySymbol: String
    let isLocked: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    
    // Computed property for background color
    private var backgroundColor: Color {
        if promo.mode == .typeList {
            // Volume promo - use category color if available
            if let categoryId = promo.categoryId,
               let category = draft.categories.first(where: { $0.id == categoryId }) {
                return Color(hex: category.hexColor)
            }
        } else if promo.mode == .combo {
            // Combo promo - use category color only if all products are from same category
            let productCategories = Set(promo.comboProducts.compactMap { productId in
                draft.products.first(where: { $0.id == productId })?.categoryId
            })
            
            // If all products are from one category, use that color
            if productCategories.count == 1, let singleCategoryId = productCategories.first {
                if let category = draft.categories.first(where: { $0.id == singleCategoryId }) {
                    return Color(hex: category.hexColor)
                }
            }
        }
        
        // Default to white
        return Color.white
    }
    
    private var promoModeText: String {
        switch promo.mode {
        case .typeList:
            return "Volume"
        case .combo:
            return "Combo"
        case .nxm:
            return "N x M"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(promo.name)
                    .font(.headline)
                    .foregroundStyle(Color.black) // Black in all modes
                
                if let category = promo.categoryName {
                    Text(category)
                        .font(.caption)
                        .foregroundStyle(Color.black.opacity(0.6)) // Dark grey in all modes
                }
                
                Text(promoModeText)
                    .font(.caption2)
                    .foregroundStyle(Color.black.opacity(0.6)) // Dark grey in all modes
            }
            
            Spacer()
            
            // Active toggle
            Toggle("", isOn: Binding(
                get: { promo.isActive },
                set: { newValue in
                    if let idx = draft.promos.firstIndex(where: { $0.id == promo.id }) {
                        draft.promos[idx].isActive = newValue
                    }
                }
            ))
            .labelsHidden()
            .disabled(isLocked)
            
            // Delete button
            if !isLocked {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.red)
                        .frame(width: 32, height: 32)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red.opacity(0.5), lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(backgroundColor)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .onTapGesture {
            onTap()
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var mockEvent = Event(
            name: "Test Event",
            date: Date(),
            currencyCode: "USD"
        )
        @State private var draft: DraftEventSettings?
        
        var body: some View {
            ZStack {
                if let draft = draft {
                    SetupPromosView(
                        draft: Binding(
                            get: { draft },
                            set: { self.draft = $0 }
                        ),
                        isLocked: false,
                        onRefresh: {}
                    )
                }
            }
            .onAppear {
                draft = DraftEventSettings(from: mockEvent)
            }
        }
    }
    
    return PreviewWrapper()
}
// MARK: - Promo Form Sheet
struct PromoFormSheet: View {
    let title: String
    @State var promoData: DraftPromo
    let availableCategories: [DraftCategory]
    let availableProducts: [DraftProduct]
    let currencyCode: String
    let currencySymbol: String
    let onSave: (DraftPromo) -> Void
    let onCancel: () -> Void
    
    @FocusState private var isNameFocused: Bool
    @State private var showingStarProductPicker = false
    @State private var categoryFilter: UUID? = nil  // For combo mode filtering
    
    init(title: String, promo: DraftPromo?, availableCategories: [DraftCategory], availableProducts: [DraftProduct], currencyCode: String, currencySymbol: String, onSave: @escaping (DraftPromo) -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self.availableCategories = availableCategories
        self.availableProducts = availableProducts
        self.currencyCode = currencyCode
        self.currencySymbol = currencySymbol
        self.onSave = onSave
        self.onCancel = onCancel
        
        if let p = promo {
            _promoData = State(initialValue: p)
        } else {
            // New Default
            _promoData = State(initialValue: DraftPromo(
                name: "",
                mode: .typeList,
                categoryId: nil,
                categoryName: nil,
                maxQuantity: 7,
                tierPrices: [:],
                isActive: true,
                sortOrder: 0
            ))
        }
    }
    
    var selectedCategory: DraftCategory? {
        availableCategories.first(where: { $0.id == promoData.categoryId })
    }
    
    var categoryProducts: [DraftProduct] {
        // If no category selected, show all active promo products
        guard let categoryId = promoData.categoryId else {
            return availableProducts.filter { $0.isActive && $0.isPromo }
        }
        // Otherwise filter by selected category
        return availableProducts.filter { $0.categoryId == categoryId && $0.isActive && $0.isPromo }
    }
    
    var filteredProducts: [DraftProduct] {
        let activePromoProducts = availableProducts.filter { $0.isActive && $0.isPromo }
        
        guard let filter = categoryFilter else {
            return activePromoProducts
        }
        
        return activePromoProducts.filter { $0.categoryId == filter }
    }
    
    var isValid: Bool {
        if promoData.mode == .combo {
            return !promoData.name.isEmpty &&
                   promoData.comboProducts.count >= 2 &&
                   promoData.comboPrice != nil &&
                   promoData.comboPrice! > 0
        } else if promoData.mode == .nxm {
            // N x M mode validation
            return !promoData.name.isEmpty &&
                   promoData.nxmN >= 2 &&
                   promoData.nxmM >= 1 &&
                   promoData.nxmN > promoData.nxmM &&
                   !promoData.nxmProducts.isEmpty
        } else {
            // Volume mode validation
            return !promoData.name.isEmpty &&
                   promoData.categoryId != nil &&
                   promoData.maxQuantity >= 2 &&
                   allTierPricesFilled
        }
    }
    
    var allTierPricesFilled: Bool {
        for qty in 2...promoData.maxQuantity {
            if promoData.tierPrices[qty] == nil || promoData.tierPrices[qty] == 0 {
                return false
            }
        }
        return true
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom header
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                
                Spacer()
                
                Text(title)
                    .font(.headline)
                
                Spacer()
                
                Button("Save") {
                    onSave(promoData)
                }
                .bold()
                .disabled(!isValid)
            }
            .padding()
            .background(Color(UIColor.systemGroupedBackground))
            
            Form {
                // MARK: - Promo Name
                Section("Promo Details") {
                    TextField("Promo Name", text: $promoData.name)
                        .focused($isNameFocused)
                        .onAppear { isNameFocused = true }
                }
                
                // MARK: - Mode Selection
                Section("Type") {
                    Picker("Promo Type", selection: $promoData.mode) {
                        Text("Volume").tag(PromoMode.typeList)
                        Text("Combo").tag(PromoMode.combo)
                        Text("N x M").tag(PromoMode.nxm)
                    }
                    .pickerStyle(.segmented)
                    
                    // Mode description
                    if promoData.mode == .typeList {
                        Text("To use with different products of the **same price**")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.top, 8)
                    } else if promoData.mode == .combo {
                        Text("To group different products into a fixed price")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.top, 8)
                    } else if promoData.mode == .nxm {
                        Text("To create a 2x1 promo type")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.top, 8)
                    }
                }
                
                // MARK: - Category Selection
                if promoData.mode == .typeList {
                    Section("Select Category") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(availableCategories) { category in
                                    CategoryButton(
                                        category: category,
                                        isSelected: promoData.categoryId == category.id,
                                        onTap: {
                                            promoData.categoryId = category.id
                                            promoData.categoryName = category.name
                                        }
                                    )
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    
                    // MARK: - Max Quantity
                    Section("Max Quantity") {
                        Stepper(value: $promoData.maxQuantity, in: 2...20) {
                            Text("\(promoData.maxQuantity) items")
                        }
                        .onChange(of: promoData.maxQuantity) { oldValue, newValue in
                            // Initialize tier prices for new quantities
                            for qty in 2...newValue {
                                if promoData.tierPrices[qty] == nil {
                                    promoData.tierPrices[qty] = 0
                                }
                            }
                            // Remove tier prices for quantities beyond max
                            for qty in (newValue + 1)...20 {
                                promoData.tierPrices.removeValue(forKey: qty)
                            }
                        }
                    }
                    
                    // MARK: - Tier Prices
                    let itemLabel = promoData.categoryName ?? "items"
                    Section("Promo Prices by Quantity") {
                        ForEach(2...promoData.maxQuantity, id: \.self) { quantity in
                            HStack {
                                Text("\(quantity) \(itemLabel):")
                                    .frame(width: 100, alignment: .leading)
                                
                                Spacer()
                                
                                TextField("Price", value: Binding(
                                    get: { promoData.tierPrices[quantity] ?? 0 },
                                    set: { promoData.tierPrices[quantity] = $0 }
                                ), format: .number.precision(.fractionLength(2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                                
                                Text(currencySymbol)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    // MARK: - Incremental Pricing
                    Section("Incremental Pricing") {
                        VStack(alignment: .leading, spacing: 12) {
                            // +N pricing (maxQuantity+1 to 9)
                            if promoData.maxQuantity < 9 {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("+\(promoData.maxQuantity) \(itemLabel):")
                                            .frame(width: 100, alignment: .leading)
                                        
                                        Spacer()
                                        
                                        TextField("Price/item", value: $promoData.incrementalPrice8to9, format: .number.precision(.fractionLength(2)))
                                            .keyboardType(.decimalPad)
                                            .multilineTextAlignment(.trailing)
                                            .frame(width: 80)
                                        
                                        Text(currencySymbol)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Text("Price per item from \(promoData.maxQuantity + 1) to 9 items")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            // +10 pricing
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("+10 \(itemLabel):")
                                        .frame(width: 100, alignment: .leading)
                                    
                                    Spacer()
                                    
                                    TextField("Price/item", value: $promoData.incrementalPrice10Plus, format: .number.precision(.fractionLength(2)))
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 80)
                                    
                                    Text(currencySymbol)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Text("Price per item from 10 items onwards")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    // MARK: - Star Products
                    Section("Star Products") {
                        // Display existing star products
                        ForEach(Array(promoData.starProducts.keys.sorted()), id: \.self) { productId in
                            if let product = availableProducts.first(where: { $0.id == productId }) {
                                StarProductRow(
                                    productName: product.name,
                                    extraCost: Binding(
                                        get: { promoData.starProducts[productId] ?? 0 },
                                        set: { promoData.starProducts[productId] = $0 }
                                    ),
                                    currencySymbol: currencySymbol,
                                    onDelete: {
                                        promoData.starProducts.removeValue(forKey: productId)
                                    }
                                )
                            }
                        }
                        
                        // Add button
                        Button {
                            showingStarProductPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Star Product")
                            }
                            .foregroundColor(.blue)
                        }
                    }
                }
                
                // MARK: - Combo Mode UI
                if promoData.mode == .combo {
                    // Category Filters
                    Section("Filter by Category") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                FilterButton(
                                    title: "All",
                                    isSelected: categoryFilter == nil,
                                    onTap: { categoryFilter = nil }
                                )
                                ForEach(availableCategories) { category in
                                    FilterButton(
                                        title: category.name,
                                        isSelected: categoryFilter == category.id,
                                        onTap: { categoryFilter = category.id }
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    // Product Selection
                    Section("Select Products for Combo") {
                        ForEach(filteredProducts) { product in
                            ComboProductRow(
                                product: product,
                                currencySymbol: currencySymbol,
                                isSelected: promoData.comboProducts.contains(product.id),
                                onToggle: {
                                    if promoData.comboProducts.contains(product.id) {
                                        promoData.comboProducts.remove(product.id)
                                    } else {
                                        promoData.comboProducts.insert(product.id)
                                    }
                                }
                            )
                        }
                    }
                    
                    // Combo Price
                    Section {
                        HStack {
                            Text("Combo Special Price")
                                .font(.body)
                            Spacer()
                            TextField("Price", value: $promoData.comboPrice, format: .number.precision(.fractionLength(2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                                .textFieldStyle(.roundedBorder)
                            Text(currencySymbol)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // MARK: - N x M Mode UI
                if promoData.mode == .nxm {
                    // N x M Controls
                    Section("Promo Structure") {
                        HStack(spacing: 12) {
                            Text("Buy")
                                .foregroundStyle(.secondary)
                            
                            TextField("N", value: $promoData.nxmN, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .frame(width: 60)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("×")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            
                            TextField("M", value: $promoData.nxmM, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .frame(width: 60)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("Pay for")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Category Filters (reuse from combo)
                    Section("Filter by Category") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                FilterButton(
                                    title: "All",
                                    isSelected: categoryFilter == nil,
                                    onTap: { categoryFilter = nil }
                                )
                                ForEach(availableCategories) { category in
                                    FilterButton(
                                        title: category.name,
                                        isSelected: categoryFilter == category.id,
                                        onTap: { categoryFilter = category.id }
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    // Product Selection
                    Section("Select Products for Promo") {
                        ForEach(filteredProducts) { product in
                            NxMProductRow(
                                product: product,
                                currencySymbol: currencySymbol,
                                isSelected: promoData.nxmProducts.contains(product.id),
                                onToggle: {
                                    if promoData.nxmProducts.contains(product.id) {
                                        promoData.nxmProducts.remove(product.id)
                                    } else {
                                        promoData.nxmProducts.insert(product.id)
                                    }
                                }
                            )
                        }
                    }
                }
            }
            }
            .sheet(isPresented: $showingStarProductPicker) {
                NavigationStack {
                    List {
                        ForEach(categoryProducts) { product in
                            Button {
                                if promoData.starProducts.keys.contains(product.id) {
                                    promoData.starProducts.removeValue(forKey: product.id)
                                } else {
                                    promoData.starProducts[product.id] = 0
                                }
                            } label: {
                                HStack {
                                    Text(product.name)
                                    Spacer()
                                    if promoData.starProducts.keys.contains(product.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Select Products")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingStarProductPicker = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

// MARK: - Category Button Component
struct CategoryButton: View {
    let category: DraftCategory
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: category.hexColor))
                    .frame(width: 60, height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                    )
                
                Text(category.name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .blue : .primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Star Product Row Component
struct StarProductRow: View {
    let productName: String
    @Binding var extraCost: Decimal
    let currencySymbol: String
    let onDelete: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Text(productName)
                .font(.system(size: 15))
            
            Spacer()
            
            Text("+")
                .foregroundStyle(.secondary)
            
            TextField("Extra cost", value: $extraCost, format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            isFocused = false
                        }
                    }
                }
            
            Text(currencySymbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.red)
                    .frame(width: 28, height: 28)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Product Picker Sheet
struct ProductPickerSheet: View {
    let products: [DraftProduct]
    let selectedProductIds: Set<UUID>
    let onToggle: (UUID) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(products) { product in
                    let isSelected = selectedProductIds.contains(product.id)
                    Button {
                        onToggle(product.id)
                    } label: {
                        HStack {
                            Text(product.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Star Products")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onCancel)
                }
            }
        }
    }
}

// MARK: - Filter Button Component
struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Combo Product Row Component
struct ComboProductRow: View {
    let product: DraftProduct
    let currencySymbol: String
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text("\(currencySymbol)\(product.price.formatted(.number.precision(.fractionLength(2))))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .gray)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
// MARK: - N x M Product Row Component
struct NxMProductRow: View {
    let product: DraftProduct
    let currencySymbol: String
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text("\(currencySymbol)\(product.price.formatted(.number.precision(.fractionLength(2))))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .gray)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

