import SwiftUI

struct SetupStockView: View {
    @Bindable var event: Event
    @Binding var draftProducts: [DraftProduct]
    var isLocked: Bool
    var mainCurrencySymbol: String

    private var visibleProducts: [Product] {
        event.products
            .filter { !$0.isDeleted }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Total stock value across all tracked products (live from event)
    private var totalStockValue: Decimal {
        visibleProducts.reduce(Decimal(0)) { sum, p in
            guard let qty = p.stockQty else { return sum }
            return sum + p.price * Decimal(qty)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(visibleProducts) { product in
                        StockRowView(
                            product: product,
                            currencySymbol: mainCurrencySymbol,
                            isLocked: isLocked,
                            onQtyChange: { newQty in
                                // Write through to live model immediately
                                product.stockQty = newQty
                                // Keep draft in sync so save/discard works correctly
                                if let idx = draftProducts.firstIndex(where: { $0.id == product.id }) {
                                    draftProducts[idx].stockQty = newQty
                                }
                            }
                        )
                        Divider().padding(.leading, 16)
                    }
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            // Footer: total stock value
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Text("Total Stock Value")
                        .font(.headline)
                    Spacer()
                    Text("\(mainCurrencySymbol)\(totalStockValue.formatted(.number.precision(.fractionLength(2))))")
                        .font(.headline)
                        .monospacedDigit()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(UIColor.secondarySystemGroupedBackground))
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
}

// MARK: - Stock Row

private struct StockRowView: View {
    let product: Product
    let currencySymbol: String
    let isLocked: Bool
    let onQtyChange: (Int?) -> Void

    @FocusState private var isFocused: Bool
    @State private var textValue: String = ""

    private var stockValue: Decimal {
        guard let qty = product.stockQty else { return 0 }
        return product.price * Decimal(qty)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Product name + price
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(.body)
                    .lineLimit(1)
                Text("\(currencySymbol)\(product.price.formatted(.number.precision(.fractionLength(2))))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Minus button
            Button {
                let current = product.stockQty ?? 0
                if current > 0 {
                    let newQty = current - 1
                    onQtyChange(newQty)
                    textValue = "\(newQty)"
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .foregroundColor(product.stockQty ?? 0 > 0 ? .blue : .gray)
            }
            .buttonStyle(.plain)
            .disabled(isLocked)

            // Quantity text field
            TextField("—", text: $textValue)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 52)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(8)
                .focused($isFocused)
                .onChange(of: textValue) { _, newVal in
                    let digits = newVal.filter { $0.isNumber }
                    if digits != newVal { textValue = digits }
                    if let qty = Int(digits) {
                        onQtyChange(qty)
                    } else if digits.isEmpty {
                        onQtyChange(nil)
                    }
                }
                .onAppear {
                    textValue = product.stockQty.map { "\($0)" } ?? ""
                }
                .onChange(of: product.stockQty) { _, newQty in
                    // Reflect external changes (e.g. from transactions) unless user is editing
                    if !isFocused {
                        textValue = newQty.map { "\($0)" } ?? ""
                    }
                }
                .disabled(isLocked)

            // Plus button
            Button {
                let current = product.stockQty ?? 0
                let newQty = current + 1
                onQtyChange(newQty)
                textValue = "\(newQty)"
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .disabled(isLocked)

            // Stock value
            Text("\(currencySymbol)\(stockValue.formatted(.number.precision(.fractionLength(2))))")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(isLocked ? 0.6 : 1.0)
    }
}
