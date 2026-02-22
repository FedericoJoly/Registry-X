import SwiftUI
import SwiftData

/// Central orchestrator for issuing full refunds.
/// Creates a linked negative transaction, marks the original, restores stock, and sends receipts.
@MainActor
class RefundService {

    // MARK: - Refund Method
    enum RefundMethod {
        case cash
        case stripe // trigger Stripe API refund (card / QR)
    }

    // MARK: - Process Refund

    static func processRefund(
        originalTransaction: Transaction,
        event: Event,
        refundMethod: RefundMethod,
        modelContext: ModelContext
    ) async throws {

        // 1. Stripe API call if needed
        if refundMethod == .stripe {
            let backendURL = event.stripeBackendURL ?? ""
            guard !backendURL.isEmpty else {
                throw RefundError.noBackend
            }
            let service = StripeNetworkService(backendURL: backendURL)

            // Resolve paymentIntentId — may be stored directly or retrieved from session
            var intentId = originalTransaction.stripePaymentIntentId

            if intentId == nil, let sessionId = originalTransaction.stripeSessionId {
                intentId = try await service.getPaymentIntentFromSession(sessionId: sessionId)
            }

            guard let finalIntentId = intentId else {
                throw RefundError.noPaymentIntent
            }

            try await service.refundPaymentIntent(intentId: finalIntentId)
        }

        // 2. Create the refund (negative) transaction
        let refundTransaction = Transaction(
            id: UUID(),
            timestamp: Date(),
            totalAmount: -originalTransaction.totalAmount,
            currencyCode: originalTransaction.currencyCode,
            note: "Refund — ref: \(originalTransaction.transactionRef ?? String(originalTransaction.id.uuidString.prefix(5)))",
            paymentMethod: originalTransaction.paymentMethod,
            paymentMethodIcon: originalTransaction.paymentMethodIcon,
            transactionRef: originalTransaction.transactionRef,
            paymentStatus: "refunded",
            receiptEmail: originalTransaction.receiptEmail
        )
        refundTransaction.isRefund = true
        refundTransaction.refundedTransactionId = originalTransaction.id

        // Mirror split entries with negated amounts
        if originalTransaction.isNWaySplit {
            let negatedEntries = originalTransaction.splitEntries.map { entry in
                SplitEntry(
                    method: entry.method,
                    methodIcon: entry.methodIcon,
                    colorHex: entry.colorHex,
                    amountInMain: -entry.amountInMain,
                    chargeAmount: -entry.chargeAmount,
                    currencyCode: entry.currencyCode,
                    cardLast4: entry.cardLast4
                )
            }
            refundTransaction.splitEntries = negatedEntries
        }

        // Copy line items (unit prices kept positive; subtotals will be negative via quantity sign is not used — mark via negating unitPrice)
        for item in originalTransaction.lineItems {
            let refundItem = LineItem(
                productName: item.productName,
                quantity: item.quantity,
                unitPrice: -item.unitPrice, // negate so subtotal = unitPrice * qty is negative
                subgroup: item.subgroup
            )
            refundTransaction.lineItems.append(refundItem)
        }

        // 3. Mark original as refunded
        originalTransaction.isRefunded = true

        // 4. Attach refund transaction to event
        event.transactions.append(refundTransaction)
        modelContext.insert(refundTransaction)

        // 5. Restore stock quantities (if stock control enabled)
        if event.isStockControlEnabled {
            for item in originalTransaction.lineItems {
                if let product = event.products.first(where: {
                    $0.name == item.productName && !$0.isDeleted
                }) {
                    product.stockQty = (product.stockQty ?? 0) + item.quantity
                }
            }
        }

        // 6. Save
        try modelContext.save()

        // 7. Send refund receipt email (cash/Bizum only — Stripe handles card/QR automatically)
        if refundMethod == .cash,
           let email = originalTransaction.receiptEmail,
           !email.isEmpty,
           let backendURL = event.stripeBackendURL {
            await ReceiptService.sendRefundReceipt(
                originalTransaction: originalTransaction,
                event: event,
                email: email,
                mailerBackendURL: backendURL
            )
        }
    }
}

// MARK: - Errors
enum RefundError: LocalizedError {
    case noBackend
    case noPaymentIntent
    case stripeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noBackend:        return "Stripe backend URL not configured"
        case .noPaymentIntent:  return "No Stripe payment intent found for this transaction"
        case .stripeFailed(let msg): return "Stripe refund failed: \(msg)"
        }
    }
}
