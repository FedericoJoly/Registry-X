import Foundation
import SwiftData

@Observable
@MainActor
class CurrencyService {
    var modelContext: ModelContext?
    
    // Fallback static rates if no DB and no Internet
    private var cachedRates: [String: Decimal] = ["USD": 1.0, "EUR": 0.92, "GBP": 0.79]
    var lastUpdated: Date?
    
    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }
    
    /// Fetches rates from Internet (open.er-api.com)
    /// Fallbacks to local DB cache if offline
    func fetchRates(base: String = "USD") async throws -> [String: Decimal] {
        let urlString = "https://open.er-api.com/v6/latest/\(base)"
        guard let url = URL(string: urlString) else { return cachedRates }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ExchangeRateResponse.self, from: data)
            
            // Update persistence if available
            updateGlobalCache(rates: response.rates, base: base)
            
            self.lastUpdated = Date()
            return response.rates
        } catch {
            print("Encoding/Network error: \(error). Using Offline Cache.")
            // Try loading from DB
            return fetchFromCache() ?? cachedRates
        }
    }
    
    // MARK: - Persistence Logic
    
    @MainActor
    private func updateGlobalCache(rates: [String: Decimal], base: String) {
        guard let context = modelContext else { return }
        
        // Simple strategy: Clear old cache or Update existing?
        // Since pairs are unique, let's update "USD/EUR" etc.
        // Assuming base is USD for simplicity of "Global Cache" typically.
        // If the user requests rates for EUR, we might get different pairs.
        // Let's stick to storing rates roughly.
        
        // For the "Last Known Rates" feature, we strictly want to store what we just fetched.
        // Let's clear and replace for simplicity in this MVP context, or upsert.
        
        let now = Date()
        
        for (code, rate) in rates {
            let pair = "\(base)/\(code)"
            let descriptor = FetchDescriptor<ExchangeRate>(predicate: #Predicate { $0.currencyPair == pair })
            
            if let existing = try? context.fetch(descriptor).first {
                existing.rate = rate
                existing.lastUpdated = now
            } else {
                let newRate = ExchangeRate(currencyPair: pair, rate: rate, lastUpdated: now)
                context.insert(newRate)
            }
        }
        
        try? context.save()
    }
    
    private func fetchFromCache() -> [String: Decimal]? {
        guard let context = modelContext else { return nil }
        
        // Try fetching "USD/..." pairs assuming base USD
        // Or if we need generic, we'd need more complex logic.
        // Simplified: Fetch all that match "USD/"
        
        let descriptor = FetchDescriptor<ExchangeRate>()
        guard let cached = try? context.fetch(descriptor), !cached.isEmpty else { return nil }
        
        var dict: [String: Decimal] = [:]
        for item in cached {
            // Parse "USD/EUR" -> "EUR"
            let components = item.currencyPair.split(separator: "/")
            if components.count == 2, components[0] == "USD" {
                dict[String(components[1])] = item.rate
            }
        }
        
        // If we found some, return. Else nil.
        return dict.isEmpty ? nil : dict
    }
}

// REST Response Structure
struct ExchangeRateResponse: Codable {
    let result: String
    let rates: [String: Decimal]
}
