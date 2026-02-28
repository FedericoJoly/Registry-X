import SwiftUI
import CoreImage.CIFilterBuiltins

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

            // Pill toggle button — purple to match QR style
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
                            .fill(Color.purple.opacity(0.92))
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
    @State private var showingQRSheet = false

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
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColor.opacity(0.4), lineWidth: 1)
        )
        .scaleEffect(isFlashing ? 1.03 : 1.0)
        // Tap the card to re-show the QR (only useful while still polling)
        .onTapGesture {
            if case .polling = job.status {
                showingQRSheet = true
            }
        }
        .sheet(isPresented: $showingQRSheet) {
            QRRescanSheet(job: job)
        }
        .onAppear {
            if case .succeeded = job.status { flashAnimation() }
        }
        .onChange(of: job.status) { _, newStatus in
            if case .succeeded = newStatus { flashAnimation() }
        }
    }

    // MARK: - Sub-views

    private var statusIndicator: some View {
        Group {
            switch job.status {
            case .polling:
                ProgressView()
                    .scaleEffect(0.75)
                    .tint(.purple)
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
        case .polling: return "Tap to show QR · Waiting for payment…"
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
        case .polling: return .purple
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

// MARK: - QR Re-scan Sheet

/// Shows the QR code again so the customer can re-scan without needing the original sheet.
private struct QRRescanSheet: View {
    @ObservedObject var job: MinimizedQRJob
    @Environment(\.dismiss) private var dismiss

    private var qrImage: UIImage? {
        generateQRCode(from: job.checkoutURL)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("Scan to Pay")
                        .font(.title2.bold())

                    Text(formattedAmount)
                        .font(.title.bold())

                    Text(job.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if let qrImage {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 250, height: 250)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(16)
                            .shadow(radius: 10)
                    } else {
                        ProgressView()
                            .scaleEffect(1.5)
                            .frame(width: 250, height: 250)
                    }

                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.purple)
                        Text("Checking payment status…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()
                        .padding(.vertical)

                    // Instructions — same as original QR screen
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Instructions")
                            .font(.headline)
                        instructionRow(number: "1", text: "Scan the QR code above")
                        instructionRow(number: "2", text: "Complete payment on your device")
                        instructionRow(number: "3", text: "App will detect completion automatically")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Pending QR Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.body.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.blue))
            Text(text)
                .font(.body)
        }
    }


    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let amount = (formatter.string(from: job.amount as NSNumber) ?? "\(job.amount)")
        return "\(amount) \(job.currency.uppercased())"
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        guard let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaled = ciImage.transformed(by: transform)
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
