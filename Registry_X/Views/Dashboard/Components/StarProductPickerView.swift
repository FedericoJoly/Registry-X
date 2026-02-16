import SwiftUI

// MARK: - Star Product Picker View
struct StarProductPickerView: View {
    let products: [DraftProduct]
    @Binding var starProducts: [UUID: Decimal]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            ForEach(products) { product in
                let isSelected = starProducts.keys.contains(product.id)
                Button {
                    // Toggle product
                    if isSelected {
                        starProducts.removeValue(forKey: product.id)
                    } else {
                        starProducts[product.id] = 0
                    }
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
    }
}
