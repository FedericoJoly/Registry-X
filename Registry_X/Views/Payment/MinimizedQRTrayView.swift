import SwiftUI

/// Floating tray that shows minimized pending QR payment sessions.
/// Anchored to the bottom-trailing corner of EventDashboardView (above the tab bar).
struct MinimizedQRTrayView: View {
    @ObservedObject var manager: QRPaymentManager

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if isExpanded && !manager.minimizedJobs.isEmpty {
                VStack(alignment: .trailing, spacing: 8) {
                    ForEach(manager.minimizedJobs) { job in
                        MinimizedQRJobCard(job: job, manager: manager)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity),
                                removal: .scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity)
                            ))
                    }
                }
                .padding(.bottom, 6)
            }

            // Pill toggle button
            if !manager.minimizedJobs.isEmpty {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(manager.minimizedJobs.count)")
                            .font(.system(size: 13, weight: .bold))

                        // Status dots
                        HStack(spacing: 3) {
                            ForEach(manager.minimizedJobs) { job in
                                Circle()
                                    .fill(dotColor(for: job.status))
                                    .frame(width: 7, height: 7)
                            }
                        }

                        Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.92))
                            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                    )
                }
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 12)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.minimizedJobs.count)
    }

    private func dotColor(for status: QRSessionStatus) -> Color {
        switch status {
        case .polling: return .yellow
        case .succeeded: return .green
        case .failed: return .red
        }
    }
}

// MARK: - Individual Job Card

private struct MinimizedQRJobCard: View {
    @ObservedObject var job: MinimizedQRJob
    var manager: QRPaymentManager

    @State private var isFlashing = false

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            statusIndicator

            VStack(alignment: .leading, spacing: 2) {
                Text(formattedAmount)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text(statusLabel)
                    .font(.system(size: 11))
                    .foregroundColor(statusColor)
            }

            Spacer(minLength: 4)

            // Action button
            actionButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    .regularMaterial
                )
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColor.opacity(0.4), lineWidth: 1)
        )
        .scaleEffect(isFlashing ? 1.03 : 1.0)
        .onAppear {
            if case .succeeded = job.status {
                flashAnimation()
            }
        }
        .onChange(of: job.status) { _, newStatus in
            if case .succeeded = newStatus {
                flashAnimation()
            }
        }
    }

    // MARK: - Sub-views

    private var statusIndicator: some View {
        Group {
            switch job.status {
            case .polling:
                ProgressView()
                    .scaleEffect(0.75)
                    .tint(.blue)
            case .succeeded:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.red)
            }
        }
        .frame(width: 24, height: 24)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch job.status {
        case .polling:
            Button(role: .destructive) {
                withAnimation {
                    manager.remove(jobId: job.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

        case .succeeded(let sessionId):
            Button {
                withAnimation {
                    manager.triggerSuccess(jobId: job.id, sessionId: sessionId)
                }
            } label: {
                Text("Register")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green))
            }
            .buttonStyle(.plain)

        case .failed:
            Button {
                withAnimation {
                    manager.remove(jobId: job.id)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let amount = (formatter.string(from: job.amount as NSNumber) ?? "\(job.amount)")
        return "\(amount) \(job.currency.uppercased())"
    }

    private var statusLabel: String {
        switch job.status {
        case .polling: return "Waiting for payment…"
        case .succeeded: return "Payment received!"
        case .failed: return "Payment failed / expired"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .polling: return .secondary
        case .succeeded: return .green
        case .failed: return .red
        }
    }

    private var borderColor: Color {
        switch job.status {
        case .polling: return .blue
        case .succeeded: return .green
        case .failed: return .red
        }
    }

    private func flashAnimation() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            isFlashing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isFlashing = false
            }
        }
    }
}
