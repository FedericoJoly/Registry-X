import Foundation
import SwiftUI
import Combine

// MARK: - Session Status

enum QRSessionStatus: Equatable {
    case polling
    case succeeded(sessionId: String)
    case failed
}

// MARK: - Minimized QR Job

/// Represents a single QR payment session that has been minimized to the tray.
/// The polling `Task` keeps running in the background regardless of sheet state.
@MainActor
class MinimizedQRJob: Identifiable, ObservableObject {
    let id: UUID
    let amount: Decimal
    let currency: String
    let description: String
    let txnRef: String
    let backendURL: String

    @Published var status: QRSessionStatus = .polling

    /// The Stripe Checkout URL — used to re-generate the QR if the customer needs to re-scan.
    let checkoutURL: String
    /// Called when Stripe confirms success — registers the transaction.
    /// Receives (sessionId, customerEmail?) so the caller can set receiptEmail.
    var onSuccess: ((String, String?) -> Void)?
    /// Background polling task — NOT cancelled on minimize.
    private(set) var pollingTask: Task<Void, Never>?

    init(
        id: UUID = UUID(),
        amount: Decimal,
        currency: String,
        description: String,
        txnRef: String,
        backendURL: String,
        checkoutURL: String,
        pollingTask: Task<Void, Never>?,
        onSuccess: ((String, String?) -> Void)?
    ) {
        self.id = id
        self.amount = amount
        self.currency = currency
        self.description = description
        self.txnRef = txnRef
        self.backendURL = backendURL
        self.checkoutURL = checkoutURL
        self.pollingTask = pollingTask
        self.onSuccess = onSuccess
    }

    func cancelPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}

// MARK: - QR Payment Manager

/// Shared manager for minimized QR payment sessions.
/// Injected as an @EnvironmentObject from EventDashboardView.
@MainActor
final class QRPaymentManager: ObservableObject {
    static let maxMinimized = 3

    @Published private(set) var minimizedJobs: [MinimizedQRJob] = []

    var canMinimize: Bool {
        minimizedJobs.count < QRPaymentManager.maxMinimized
    }

    var atLimit: Bool {
        minimizedJobs.count >= QRPaymentManager.maxMinimized
    }

    // MARK: - Minimize

    /// Adds a QR session to the minimized tray.
    /// - Parameters:
    ///   - amount: Total charge amount
    ///   - currency: Currency code
    ///   - txnRef: Transaction reference string
    ///   - backendURL: Stripe backend URL for status polling
    ///   - pollingTask: The background polling Task (must NOT be cancelled before passing here)
    ///   - sessionId: The Stripe checkout session ID (already obtained when showing QR)
    ///   - checkoutURL: The Stripe Checkout URL for QR re-generation if customer needs to re-scan
    ///   - onSuccess: Closure to register the transaction when Stripe confirms payment
    func minimize(
        amount: Decimal,
        currency: String,
        description: String,
        txnRef: String,
        backendURL: String,
        pollingTask: Task<Void, Never>,
        sessionId: String,
        checkoutURL: String,
        onSuccess: @escaping (String, String?) -> Void
    ) {
        guard canMinimize else { return }

        let job = MinimizedQRJob(
            amount: amount,
            currency: currency,
            description: description,
            txnRef: txnRef,
            backendURL: backendURL,
            checkoutURL: checkoutURL,
            pollingTask: pollingTask,
            onSuccess: onSuccess
        )


        minimizedJobs.append(job)

        let capturedJobId = job.id
        // Use a detached task so network polling runs off the main actor
        Task.detached { [weak self] in
            await self?.watchSession(jobId: capturedJobId, sessionId: sessionId, backendURL: backendURL)
        }
    }

    // MARK: - Session Watcher

    /// Polls Stripe for session completion independently of the view's own polling Task.
    /// nonisolated so it runs off the main thread; dispatches results back via MainActor.
    private func watchSession(jobId: UUID?, sessionId: String, backendURL: String) async {
        guard let jobId else { return }

        // Poll for up to 5 minutes (20 × 15 s), matching StripeQRPaymentView behaviour
        for attempt in 0..<20 {
            if Task.isCancelled { return }

            let delay: UInt64 = attempt == 0 ? 5_000_000_000 : 15_000_000_000
            try? await Task.sleep(nanoseconds: delay)

            if Task.isCancelled { return }

            do {
                let service = StripeNetworkService(backendURL: backendURL)
                let statusDict = try await service.checkSessionStatus(sessionId: sessionId)

                if Task.isCancelled { return }

                if let paymentStatus = statusDict["status"] as? String,
                   paymentStatus == "paid" || paymentStatus == "complete" {
                    let customerEmail = statusDict["customer_email"] as? String
                    await MainActor.run {
                        guard let job = self.minimizedJobs.first(where: { $0.id == jobId }) else { return }
                        if case .polling = job.status {
                            job.status = .succeeded(sessionId: sessionId)
                            // Auto-register after a brief moment so the user sees the success indicator
                            Task {
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                await MainActor.run {
                                    self.triggerSuccess(jobId: jobId, sessionId: sessionId, customerEmail: customerEmail)
                                }
                            }
                        }
                    }
                    return
                }
            } catch {
                // Continue polling on transient network errors
            }
        }

        // Polling timed out — mark as failed
        await MainActor.run {
            guard let job = self.minimizedJobs.first(where: { $0.id == jobId }) else { return }
            if case .polling = job.status {
                job.status = .failed
            }
        }
    }

    // MARK: - Actions

    /// Triggers the success callback and removes the job from the tray.
    func triggerSuccess(jobId: UUID, sessionId: String, customerEmail: String? = nil) {
        guard let job = minimizedJobs.first(where: { $0.id == jobId }) else { return }
        job.onSuccess?(sessionId, customerEmail)
        remove(jobId: jobId)
    }

    /// Removes a job from the tray (used for failed or manually dismissed cards).
    func remove(jobId: UUID) {
        if let job = minimizedJobs.first(where: { $0.id == jobId }) {
            job.cancelPolling()
        }
        minimizedJobs.removeAll { $0.id == jobId }
    }
}
