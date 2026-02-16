import SwiftUI

struct SetupCategoriesView: View {
    @Binding var categories: [DraftCategory]
    @Binding var isSingleCategoryMode: Bool
    var isLocked: Bool
    
    // Sheet State
    @State private var showingAddSheet = false
    
    // Deletion State
    @State private var showingDeleteAlert = false
    @State private var categoryIdToDelete: UUID?
    
    // Reordering State
    @State private var isEditingMode = false
    
    // Color Picker State (for editing existing categories in their cards)
    @State private var categoryIDEditingColor: UUID?
    
    var body: some View {
        ZStack { // ZStack for Color Picker Overlay
            VStack(spacing: 0) { // Zero spacing, List handles it
                
                // MARK: - Header Actions
                HStack(alignment: .center) {
                    if !categories.isEmpty {
                        Text(isEditingMode ? "Drag handles to reorder." : "Tip: tap a category to edit color, hold and drag to reorder.")
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
                
                // LIST
                if categories.isEmpty {
                     ContentUnavailableView("No Categories", systemImage: "tag", description: Text("Add a category to organize products."))
                        .padding(.top, 40)
                        .background(Color(UIColor.systemGray6))
                } else {
                    List {
                        // Safe Binding Loop
                        // We iterate over the *values* (categories) to get stable IDs.
                        // Then we find the index dynamically. This prevents accessing stale indices.
                        ForEach(categories) { category in
                            if categories.contains(where: { $0.id == category.id }) {
                                // Manual Binding via ID Lookup
                                // This prevents index-out-of-range crashes during deletions/moves
                                let binding = Binding<DraftCategory>(
                                    get: { 
                                        // If not found (e.g. just deleted), return the captured 'category' (state value)
                                        // This keeps the view stable until it is removed by SwiftUI
                                        categories.first(where: { $0.id == category.id }) ?? category
                                    },
                                    set: { newValue in
                                        if let idx = categories.firstIndex(where: { $0.id == category.id }) {
                                            categories[idx] = newValue
                                        }
                                    }
                                )
                                
                                CategoryRow(
                                    category: binding,
                                    isSingleCategoryMode: isSingleCategoryMode,
                                    allCategories: $categories,
                                    isLocked: isLocked,
                                    isEditing: isEditingMode,
                                    onColorTap: {
                                        categoryIDEditingColor = category.id
                                    },
                                    onDelete: {
                                        categoryIdToDelete = category.id
                                        showingDeleteAlert = true
                                    }
                                )
                                .onLongPressGesture(minimumDuration: 1.0) {
                                     withAnimation { isEditingMode.toggle() }
                                }
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowBackground(Color.clear)
                            }
                        }
                        .onMove(perform: moveCategory)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, .constant(isEditingMode ? .active : .inactive))
                    .animation(.default, value: isEditingMode)
                }
            }
            .background(Color(UIColor.systemGray6))
            
            // MARK: - Sheet
            .sheet(isPresented: $showingAddSheet) {
                CategoryFormSheet(
                    title: "New Category",
                    category: nil,
                    onSave: { new in
                        addCategory(new)
                        showingAddSheet = false
                    },
                    onCancel: { showingAddSheet = false }
                )
                .presentationDetents([.fraction(0.6)])
                .presentationCornerRadius(20)
            }
            
            // MARK: - Alert
            .alert("Delete Category?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    if let id = categoryIdToDelete {
                       deleteCategory(id: id)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete this category?")
            }
            
            // GLOBAL COLOR PICKER OVERLAY
            if let editingID = categoryIDEditingColor {
                if let idx = categories.firstIndex(where: { $0.id == editingID }) {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            categoryIDEditingColor = nil
                        }
                        .transition(.opacity)
                    
                    ColorPickerSheet(selectedColorHex: $categories[idx].hexColor) {
                        categoryIDEditingColor = nil
                    }
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(1)
                } else {
                     // ID not found (weird state), cleanup
                     Color.clear.onAppear { categoryIDEditingColor = nil }
                }
            }
        }
    }
    
    // Logic
    private func addCategory(_ new: DraftCategory) {
        var category = new
        // Auto-assign sort order
        category.sortOrder = (categories.map { $0.sortOrder }.max() ?? -1) + 1
        categories.append(category)
    }
    
    private func deleteCategory(id: UUID) {
        categories.removeAll { $0.id == id }
    }
    
    private func moveCategory(from source: IndexSet, to destination: Int) {
        // Direct array manipulation
        categories.move(fromOffsets: source, toOffset: destination)
        
        // Re-assign sortOrder indices
        for (index, _) in categories.enumerated() {
            categories[index].sortOrder = index
        }
    }
}

// Subcomponent: Category Row
struct CategoryRow: View {
    @Binding var category: DraftCategory
    var isSingleCategoryMode: Bool
    @Binding var allCategories: [DraftCategory]
    var isLocked: Bool
    var isEditing: Bool
    var onColorTap: () -> Void
    var onDelete: () -> Void
    
    @State private var isRenaming = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            
            // Name Section
            if isRenaming {
                TextField("Category Name", text: $category.name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit {
                        isRenaming = false
                    }
                    .submitLabel(.done)
            } else {
                Text(category.name)
                    .font(.headline)
                    .foregroundStyle(Color.black) // Black in all modes
                    .strikethrough(!category.isEnabled)
                    .padding(.leading, 4)
            }
            
            Spacer()
            
            if !isEditing {
                // Toggle
                Toggle("", isOn: Binding(
                    get: { category.isEnabled },
                    set: { newValue in
                        if isSingleCategoryMode && newValue {
                            // Radio button behavior: disable all others first
                            for i in allCategories.indices {
                                if allCategories[i].id != category.id {
                                    allCategories[i].isEnabled = false
                                }
                            }
                        }
                        category.isEnabled = newValue
                    }
                ))
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                    .disabled(isLocked)
                
                // Edit / Rename Button
                Button(action: {
                    if isRenaming {
                        isRenaming = false
                    } else {
                        isRenaming = true
                        isFocused = true
                    }
                }) {
                     Image(systemName: isRenaming ? "checkmark" : "pencil")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 0, green: 0.5, blue: 0)) // Dark Green
                        .frame(width: 32, height: 32)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(red: 0, green: 0.5, blue: 0).opacity(0.5), lineWidth: 1.5)
                        )
                }
                .buttonStyle(.borderless)
                .disabled(isLocked)
                
                // Color Picker Button
                Button(action: onColorTap) {
                     Image(systemName: "paintpalette.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 32, height: 32)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.black.opacity(0.5), lineWidth: 1.5)
                        )
                }
                .buttonStyle(.borderless) // CRITICAL FIX for List
                .disabled(isLocked)

                // Delete
                Button(action: onDelete) {
                     Image(systemName: "trash")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.red)
                        .frame(width: 32, height: 32)
                        .background(Color.white) // Fixed White
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red.opacity(0.5), lineWidth: 1.5)
                        )
                }
                .buttonStyle(.borderless)
                .disabled(isLocked)
            }
        }
        .padding(12)
        .background(Color(hex: category.hexColor)) // REMOVED OPACITY per user request
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black.opacity(0.05), lineWidth: 1) // Added subtle border for structure
        )
        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
    }
}

// Custom Grid Color Picker
struct ColorPickerSheet: View {
    @Binding var selectedColorHex: String
    var onClose: () -> Void
    
    // Grid Setup: 6 Columns Fixed
    let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Select Color")
                .font(.default)
                .padding(.top, 15)
            
            // Fixed Grid for 60 items
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(GradientPalette.allColors, id: \.self) { hex in
                    Button(action: {
                        selectedColorHex = hex
                        onClose()
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 3) // Gray border request
                                )
                                .shadow(color: .black.opacity(0.1), radius: 1)
                            
                            // Selection Indicator
                            if selectedColorHex == hex {
                                Image(systemName: "checkmark")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .shadow(color: .white.opacity(0.5), radius: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            
            Button("Close") {
                onClose()
            }
            .buttonStyle(.bordered)
            .padding(.bottom, 16)
        }
        .frame(width: 300)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.2), radius: 20)
    }
}

// MARK: - Category Form Sheet
struct CategoryFormSheet: View {
    let title: String
    @State var categoryData: DraftCategory
    let onSave: (DraftCategory) -> Void
    let onCancel: () -> Void
    
    @FocusState private var isNameFocused: Bool
    
    // Grid Setup for color picker
    let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)
    
    // Init wrapper to populate state
    init(title: String, category: DraftCategory?, onSave: @escaping (DraftCategory) -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self.onSave = onSave
        self.onCancel = onCancel
        
        if let cat = category {
            _categoryData = State(initialValue: cat)
        } else {
            // New Default - pick a random color
            let _: Set<String> = [] // Can't access parent state here
            let available = GradientPalette.allColors
            let randomColor = available.randomElement() ?? "#66BB6A"
            
            _categoryData = State(initialValue: DraftCategory(
                name: "",
                hexColor: randomColor,
                isEnabled: true,
                sortOrder: 0
            ))
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Category Name") {
                    TextField("Enter category name", text: $categoryData.name)
                        .focused($isNameFocused)
                        .onAppear { isNameFocused = true }
                }
                
                Section("Color") {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(GradientPalette.allColors, id: \.self) { hex in
                            Button(action: {
                                categoryData.hexColor = hex
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 30, height: 30)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 3)
                                        )
                                        .shadow(color: .black.opacity(0.1), radius: 1)
                                    
                                    // Selection Indicator
                                    if categoryData.hexColor == hex {
                                        Image(systemName: "checkmark")
                                            .font(.headline)
                                            .foregroundColor(.black)
                                            .shadow(color: .white.opacity(0.5), radius: 1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
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
                        onSave(categoryData)
                    }
                    .bold()
                    .foregroundStyle(.blue)
                    .disabled(categoryData.name.isEmpty)
                }
            }
        }
    }
}

// Gradient Palette Definitions (60 Colors)
struct GradientPalette {
    // Ordered Dark (Left) -> Light (Right)
    // 10 Rows x 6 Columns = 60 Colors
    static let allColors: [String] = [
        // 1. Greens (Dark -> Light)
        "#1B5E20", "#2E7D32", "#43A047", "#66BB6A", "#A5D6A7", "#C8E6C9",
        // 2. Teals (Dark -> Light)
        //"#004D40", "#00695C", "#00897B", "#26A69A", "#80CBC4", "#B2DFDB",
        // 3. Blues (Dark -> Light)
        "#0D47A1", "#1565C0", "#1E88E5", "#42A5F5", "#90CAF9", "#BBDEFB",
        // 4. Indigos (Dark -> Light)
        //"#1A237E", "#283593", "#3949AB", "#5C6BC0", "#9FA8DA", "#C5CAE9",
        // 5. Purples (Dark -> Light)
        "#4A148C", "#6A1B9A", "#8E24AA", "#AB47BC", "#CE93D8", "#E1BEE7",
        // 6. Pinks (Dark -> Light)
        //"#880E4F", "#AD1457", "#D81B60", "#EC407A", "#F48FB1", "#F8BBD0",
        // 7. Reds (Dark -> Light)
        "#B71C1C", "#C62828", "#E53935", "#EF5350", "#EF9A9A", "#FFCDD2",
        // 8. Oranges (Dark -> Light)
        //"#E65100", "#EF6C00", "#F57C00", "#FF9800", "#FFCC80", "#FFE0B2",
        // 9. Yellows (Gold -> Pale)
        "#F57F17", "#F9A825", "#FBC02D", "#FDD835", "#FFF59D", "#FFF9C4",
        // 10. Browns / Greys (Dark -> Light)
        "#3E2723", "#5D4037", "#8D6E63", "#BCAAA4", "#D7CCC8", "#E0E0E0"
    ]
}


#Preview {
    SetupCategoriesView_PreviewWrapper()
}

private struct SetupCategoriesView_PreviewWrapper: View {
    // Mock Data mimicking DraftCategory struct structure
    // Assumes DraftCategory is available in the module scope
    @State private var categories: [DraftCategory] = [
        DraftCategory(name: "Groceries", hexColor: "#66BB6A", isEnabled: true, sortOrder: 0),
        DraftCategory(name: "Rent", hexColor: "#42A5F5", isEnabled: true, sortOrder: 1),
        DraftCategory(name: "Entertainment", hexColor: "#AB47BC", isEnabled: false, sortOrder: 2)
    ]
    @State private var isSingleMode = false
    
    var body: some View {
        SetupCategoriesView(categories: $categories, isSingleCategoryMode: $isSingleMode, isLocked: false)
    }
}
