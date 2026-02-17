import SwiftUI

struct SetupProductsView: View {
    @Binding var products: [DraftProduct]
    var availableCategories: [DraftCategory]
    var currencyCode: String
    var isLocked: Bool
    var event: Event // Added to check transactions
    
    // Sheet State
    @State private var showingAddSheet = false
    @State private var editingProduct: DraftProduct? // If set, showing edit sheet
    @State private var duplicatingProduct: DraftProduct? // Product being duplicated

    // Deletion State
    @State private var showingDeleteAlert = false
    @State private var productIdToDelete: UUID?
    @State private var showingTransactedProductAlert = false // New alert
    
    // Reordering State
    @State private var isEditingMode = false
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                
                // MARK: - Header Actions
                HStack(alignment: .center) {
                    if !products.isEmpty {
                        Text(isEditingMode ? "Drag handles to reorder." : "Tip: hold and drag a product to reorder it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Spacer()
                    }
                    
                    Spacer()
                    
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 30)) // Bigger
                            .foregroundStyle(.blue)
                    }
                    .disabled(isLocked)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(UIColor.systemGray6))
                
                // MARK: - Product List
                if products.isEmpty {
                    ContentUnavailableView("No Products", systemImage: "cart", description: Text("Add products to start selling."))
                        .padding(.top, 40)
                        .background(Color(UIColor.systemGray6))
                } else {
                    List {
                        // Safe Binding Loop (Same pattern as Categories to prevent crash)
                        ForEach(products) { product in
                            if products.contains(where: { $0.id == product.id }) {
                                let binding = Binding<DraftProduct>(
                                    get: {
                                        products.first(where: { $0.id == product.id }) ?? product
                                    },
                                    set: { newValue in
                                        if let idx = products.firstIndex(where: { $0.id == product.id }) {
                                            products[idx] = newValue
                                        }
                                    }
                                )
                                
                                ProductRow(
                                    product: binding,
                                    categoryColor: categoryColor(for: product.categoryId),
                                    currencyCode: currencyCode,
                                    isLocked: isLocked,
                                    isEditing: isEditingMode,
                                    onTap: {
                                        if !isLocked && !isEditingMode {
                                            editingProduct = product
                                        }
                                    },
                                    onDuplicate: { duplicatingProduct = product },
                                    onDelete: {
                                        productIdToDelete = product.id
                                        showingDeleteAlert = true
                                    }
                                )
                                .id(product.id)
                                .onLongPressGesture(minimumDuration: 0.5) {
                                    withAnimation { isEditingMode.toggle() }
                                }
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowBackground(Color.clear)
                            }
                        }
                        .onMove(perform: moveProduct)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, .constant(isEditingMode ? .active : .inactive))
                }
            }
        }
        .background(Color(UIColor.systemGray6))
        
        // MARK: - Sheets
        
        // 1. ADD NEW
        .sheet(isPresented: $showingAddSheet) {
            ProductFormSheet(
                title: "New Product",
                product: nil, // New
                availableCategories: availableCategories,
                currencyCode: currencyCode,
                onSave: { new in
                    addProduct(new)
                    showingAddSheet = false
                },
                onCancel: { showingAddSheet = false }
            )
            .presentationDetents([.fraction(0.75)])
            .presentationCornerRadius(20)
        }
        
        // 2. EDIT
        .sheet(item: $editingProduct) { productToEdit in
            ProductFormSheet(
                title: "Edit Product",
                product: productToEdit,
                availableCategories: availableCategories,
                currencyCode: currencyCode,
                onSave: { updated in
                    updateProduct(updated)
                    editingProduct = nil
                },
                onCancel: { editingProduct = nil }
            )
            .presentationDetents([.fraction(0.75)])
            .presentationCornerRadius(20)
        }
        
        // 3. DUPLICATE
        .sheet(item: $duplicatingProduct) { productToDuplicate in
            ProductFormSheet(
                title: "Duplicate Product",
                product: DraftProduct(
                    name: "\(productToDuplicate.name) (Copy)",
                    price: productToDuplicate.price,
                    categoryId: productToDuplicate.categoryId,
                    subgroup: productToDuplicate.subgroup,
                    isActive: productToDuplicate.isActive,
                    isPromo: productToDuplicate.isPromo,
                    sortOrder: 0 // Will be set on add
                ),
                availableCategories: availableCategories,
                currencyCode: currencyCode,
                onSave: { duplicated in
                    addProductAfter(duplicated, after: productToDuplicate.id)
                    duplicatingProduct = nil
                },
                onCancel: { duplicatingProduct = nil }
            )
            .presentationDetents([.fraction(0.75)])
            .presentationCornerRadius(20)
        }
        
        // MARK: - Alerts
        .alert("Delete Product?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let id = productIdToDelete {
                    deleteProduct(id: id)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this product?")
        }
        
        // New alert for transacted products
        .alert("Can't Delete Transacted Product", isPresented: $showingTransactedProductAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This product has been used in transactions and cannot be deleted. Consider disabling it instead.")
        }
    }
    
    // MARK: - Logic
    
    private func categoryColor(for id: UUID?) -> String {
        guard let id = id else { return "#FFFFFF" } // White default if no category
        return availableCategories.first(where: { $0.id == id })?.hexColor ?? "#FFFFFF"
    }
    
    
    private func addProduct(_ new: DraftProduct) {
        var product = new
        // Auto-assign order
        product.sortOrder = (products.map { $0.sortOrder }.max() ?? -1) + 1
        products.append(product)
    }
    
    private func addProductAfter(_ new: DraftProduct, after id: UUID) {
        var product = new
        
        // Find index and insert after
        if let index = products.firstIndex(where: { $0.id == id }) {
            if index + 1 < products.count {
                products.insert(product, at: index + 1)
            } else {
                products.append(product)
            }
        } else {
            products.append(product)
        }
        
        // Re-index all
        for (i, _) in products.enumerated() {
            products[i].sortOrder = i
        }
    }
    
    private func updateProduct(_ updated: DraftProduct) {
        if let idx = products.firstIndex(where: { $0.id == updated.id }) {
            products[idx] = updated
        }
    }
    
    
    private func deleteProduct(id: UUID) {
        // Check if product has been used in any transactions
        guard let product = products.first(where: { $0.id == id }) else { return }
        
        let isUsedInTransactions = event.transactions.contains { transaction in
            transaction.lineItems.contains { $0.productName == product.name }
        }
        
        if isUsedInTransactions {
            showingTransactedProductAlert = true
            return
        }
        
        products.removeAll { $0.id == id }
    }
    
    private func moveProduct(from source: IndexSet, to destination: Int) {
        products.move(fromOffsets: source, toOffset: destination)
        for (index, _) in products.enumerated() {
            products[index].sortOrder = index
        }
    }
}

// MARK: - Product Row Component
struct ProductRow: View {
    @Binding var product: DraftProduct
    var categoryColor: String
    var currencyCode: String
    var isLocked: Bool
    var isEditing: Bool
    var onTap: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void
    
    // Determine contrasting text color (Simple logic)
    var textColor: Color {
        // Since we are using user-defined hex colors, we need to guess contrast.
        // For simplicity, let's assume pastel palette = Black text is safer.
        // Or we can just use .primary and let the system handle it if background is ignored?
        // User said "Color the PRODUCT with the same color".
        return .black // Assuming light pastel backgrounds as requested previously
    }
    
    var body: some View {
        HStack(spacing: 12) {
            
            // Info
            VStack(alignment: .leading, spacing: 2) { // Compact spacing
                Text(product.name)
                    .font(.headline)
                    .foregroundStyle(textColor)
                
                if !product.subgroup.isEmpty {
                    Text(product.subgroup)
                        .font(.caption)
                        .foregroundStyle(textColor.opacity(0.8))
                }
                
                Text(product.price.formatted(.currency(code: currencyCode)))
                    .font(.subheadline)
                    .foregroundStyle(textColor.opacity(0.6)) // "Secondary style"
            }
            .padding(.vertical, 4) // Compact vertical padding
            
            Spacer()
            
            if !isEditing {
                // Stacked Toggles
                VStack(alignment: .trailing, spacing: 4) { // Compact spacing
                    // Active (Top)
                    HStack(spacing: 8) {
                        Text("Active")
                            .font(.caption2)
                            .foregroundStyle(textColor.opacity(0.7))
                        Toggle("", isOn: $product.isActive)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: .green))
                            .scaleEffect(0.6) // Smaller toggle to save space
                    }
                    
                    // Promo (Bottom)
                    HStack(spacing: 8) {
                        Text("Promo")
                            .font(.caption2)
                            .foregroundStyle(textColor.opacity(0.7))
                        Toggle("", isOn: $product.isPromo)
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: .purple))
                            .scaleEffect(0.6) // Smaller toggle
                    }
                }
                .disabled(isLocked)
                
                // Actions
                VStack(spacing: 8) { // Compact spacing
                    ProductActionButton(icon: "doc.on.doc", color: .yellow, action: onDuplicate)
                    ProductActionButton(icon: "trash", color: .red, action: onDelete)
                }
                .padding(.leading, 8)
                .disabled(isLocked)
            }
        }
        .padding(12) // Compact Card Padding
        .background(Color(hex: categoryColor)) // Product gets Category Color
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .onTapGesture {
            onTap()
        }
    }
}

struct ProductActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
             Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(Color.white) // Fixed White
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(color.opacity(0.5), lineWidth: 1.5) // Matching border
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Product Form Sheet
struct ProductFormSheet: View {
    let title: String
    @State var productData: DraftProduct
    let availableCategories: [DraftCategory]
    let currencyCode: String
    let onSave: (DraftProduct) -> Void
    let onCancel: () -> Void
    
    @FocusState private var isNameFocused: Bool
    
    // Init wrapper to populate state
    init(title: String, product: DraftProduct?, availableCategories: [DraftCategory], currencyCode: String, onSave: @escaping (DraftProduct) -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self.availableCategories = availableCategories
        self.currencyCode = currencyCode
        self.onSave = onSave
        self.onCancel = onCancel
        
        if let p = product {
            _productData = State(initialValue: p)
        } else {
            // New Default
            _productData = State(initialValue: DraftProduct(name: "", price: 0.0, categoryId: nil, subgroup: "", isActive: true, isPromo: false, sortOrder: 0))
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Product Name", text: $productData.name)
                        .focused($isNameFocused)
                        .onAppear { isNameFocused = true }
                    
                    TextField("Price", value: $productData.price, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                }
                
                Section("Organization") {
                    Picker("Category", selection: $productData.categoryId) {
                        Text("None").tag(UUID?.none)
                        ForEach(availableCategories) { cat in
                            Text(cat.name).tag(cat.id as UUID?)
                        }
                    }
                    
                    TextField("Subgroup", text: $productData.subgroup)
                }
                
                Section("Settings") {
                    Toggle("Active", isOn: $productData.isActive)
                    Toggle("Promo Eligible", isOn: $productData.isPromo)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(productData)
                    }
                    .bold()
                    .foregroundStyle(.blue) // Explicit Blue
                    .disabled(productData.name.isEmpty)
                }
            }
        }
    }
}
