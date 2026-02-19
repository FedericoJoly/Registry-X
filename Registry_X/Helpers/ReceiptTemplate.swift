import Foundation

/// Receipt HTML template generator for custom (non-Stripe) payment receipts
struct ReceiptTemplate {
    
    /// Generates a clean, professional HTML email receipt
    static func generateReceiptHTML(
        event: Event,
        transaction: Transaction,
        customerEmail: String
    ) -> String {
        // Format date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let formattedDate = dateFormatter.string(from: transaction.timestamp)
        
        // Format amount (main currency total)
        let currencySymbol = event.currencies.first(where: { $0.code == transaction.currencyCode })?.symbol ?? transaction.currencyCode
        let formattedAmount = "\(currencySymbol)\(transaction.totalAmount.formatted(.number.precision(.fractionLength(2))))"
        
        // Get company name from Company settings
        let companyName = event.companyName ?? event.name
        
        // Build line items HTML
        var lineItemsHTML = ""
        for item in transaction.lineItems {
            let itemTotal = item.unitPrice * Decimal(item.quantity)
            let formattedItemTotal = "\(currencySymbol)\(itemTotal.formatted(.number.precision(.fractionLength(2))))"
            let displayName = item.subgroup != nil ? "\(item.productName) (\(item.subgroup!))" : item.productName
            
            lineItemsHTML += """
            <tr>
                <td style="padding: 8px; border-bottom: 1px solid #eee;">\(item.quantity)x</td>
                <td style="padding: 8px; border-bottom: 1px solid #eee;">\(displayName)</td>
                <td style="padding: 8px; border-bottom: 1px solid #eee; text-align: right;">\(formattedItemTotal)</td>
            </tr>
            """
        }
        
        // Helper: format amount in a given currency code using event XR rates
        func format(mainAmount: Decimal, chargeCode: String) -> String {
            let sym = event.currencies.first(where: { $0.code == chargeCode })?.symbol ?? chargeCode
            let mainCode = event.currencies.first(where: { $0.isMain })?.code ?? transaction.currencyCode
            let displayAmount: Decimal
            if chargeCode == mainCode {
                displayAmount = mainAmount
            } else {
                let rate = event.currencies.first(where: { $0.code == chargeCode })?.rate ?? 1
                displayAmount = mainAmount * rate
            }
            return "\(sym)\(displayAmount.formatted(.number.precision(.fractionLength(2))))"
        }
        
        // Build payment method section (split-aware)
        let paymentSectionHTML: String
        if transaction.isSplit,
           let a1 = transaction.splitAmount1, let c1 = transaction.splitCurrencyCode1,
           let splitMethod = transaction.splitMethod, let a2 = transaction.splitAmount2, let c2 = transaction.splitCurrencyCode2 {
            
            let method1Name: String
            switch transaction.paymentMethod {
            case .cash: method1Name = "Cash"
            case .transfer: method1Name = "Bank Transfer"
            case .card: method1Name = "Card"
            case .other:
                if transaction.paymentMethodIcon == "phone.fill" { method1Name = "Bizum" }
                else { method1Name = "Other" }
            }
            let method2Name: String
            switch PaymentMethod(rawValue: splitMethod) ?? .cash {
            case .cash: method2Name = "Cash"
            case .transfer: method2Name = "Bank Transfer"
            case .card: method2Name = "Card"
            case .other: method2Name = "Bizum"
            }
            
            paymentSectionHTML = """
            <div style="padding: 15px; background-color: #f0f7ff; border-left: 4px solid #667eea; border-radius: 4px; margin-bottom: 20px;">
                <p style="margin: 0 0 10px 0; font-size: 12px; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Split Payment</p>
                <table style="width: 100%;">
                    <tr>
                        <td style="font-size: 15px; font-weight: 600; color: #333; padding-bottom: 6px;">\(method1Name)</td>
                        <td style="font-size: 15px; font-weight: 600; color: #667eea; text-align: right; padding-bottom: 6px;">\(format(mainAmount: a1, chargeCode: c1))</td>
                    </tr>
                    <tr>
                        <td style="font-size: 15px; font-weight: 600; color: #333;">\(method2Name)</td>
                        <td style="font-size: 15px; font-weight: 600; color: #667eea; text-align: right;">\(format(mainAmount: a2, chargeCode: c2))</td>
                    </tr>
                </table>
            </div>
            """
        } else {
            let paymentMethodDisplay: String
            switch transaction.paymentMethod {
            case .cash: paymentMethodDisplay = "Cash"
            case .transfer: paymentMethodDisplay = "Bank Transfer"
            case .card: paymentMethodDisplay = "Card"
            case .other:
                if transaction.paymentMethodIcon == "phone.fill" { paymentMethodDisplay = "Bizum" }
                else { paymentMethodDisplay = "Other" }
            }
            paymentSectionHTML = """
            <div style="padding: 15px; background-color: #f0f7ff; border-left: 4px solid #667eea; border-radius: 4px; margin-bottom: 20px;">
                <p style="margin: 0 0 5px 0; font-size: 12px; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Payment Method</p>
                <p style="margin: 0; font-size: 16px; font-weight: 600; color: #333;">\(paymentMethodDisplay)</p>
            </div>
            """
        }
        
        // Build HTML
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Receipt - \(companyName)</title>
        </head>
        <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5;">
            <div style="max-width: 600px; margin: 0 auto; background-color: white; border-radius: 12px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
                <!-- Header -->
                <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 30px; text-align: center; color: white;">
                    <h1 style="margin: 0; font-size: 28px; font-weight: 600;">\(companyName)</h1>
                    <p style="margin: 10px 0 0 0; font-size: 16px; opacity: 0.9;">Receipt</p>
                </div>
                
                <!-- Content -->
                <div style="padding: 30px;">
                    <!-- Event Info -->
                    <div style="margin-bottom: 25px; padding-bottom: 20px; border-bottom: 2px solid #f0f0f0;">
                        <p style="margin: 0 0 8px 0; color: #666; font-size: 14px;">Event</p>
                        <p style="margin: 0; font-size: 18px; font-weight: 600; color: #333;">\(event.name)</p>
                        <p style="margin: 8px 0 0 0; color: #666; font-size: 14px;">\(formattedDate)</p>
                    </div>
                    
                    <!-- Line Items -->
                    <table style="width: 100%; border-collapse: collapse; margin-bottom: 20px;">
                        <thead>
                            <tr style="background-color: #f8f9fa;">
                                <th style="padding: 12px 8px; text-align: left; font-size: 12px; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Qty</th>
                                <th style="padding: 12px 8px; text-align: left; font-size: 12px; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Item</th>
                                <th style="padding: 12px 8px; text-align: right; font-size: 12px; color: #666; text-transform: uppercase; letter-spacing: 0.5px;">Amount</th>
                            </tr>
                        </thead>
                        <tbody>
                            \(lineItemsHTML)
                        </tbody>
                    </table>
                    
                    <!-- Total -->
                    <div style="padding: 20px; background-color: #f8f9fa; border-radius: 8px; margin-bottom: 20px;">
                        <table style="width: 100%;">
                            <tr>
                                <td style="font-size: 18px; font-weight: 600; color: #333;">Total</td>
                                <td style="font-size: 24px; font-weight: 700; color: #667eea; text-align: right;">\(formattedAmount)</td>
                            </tr>
                        </table>
                    </div>
                    
                    <!-- Payment Details (split-aware) -->
                    \(paymentSectionHTML)
                    
                    \(transaction.transactionRef.map { ref in
                        """
                        <div style="margin-top: 15px;">
                            <p style="margin: 0 0 5px 0; font-size: 12px; color: #999; text-transform: uppercase; letter-spacing: 0.5px;">Reference</p>
                            <p style="margin: 0; font-size: 14px; color: #666; font-family: monospace;">\(ref)</p>
                        </div>
                        """
                    } ?? "")
                    
                    <!-- Footer Message -->
                    <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #eee; text-align: center;">
                        <p style="margin: 0; font-size: 14px; color: #999;">Thank you for your purchase!</p>
                        <p style="margin: 10px 0 0 0; font-size: 12px; color: #ccc;">This receipt was sent to \(customerEmail)</p>
                    </div>
                </div>
            </div>
        </body>
        </html>
        """
    }
    
    /// Generates email subject for receipt
    static func generateSubject(eventName: String) -> String {
        return "\(eventName) - Receipt"
    }
}
