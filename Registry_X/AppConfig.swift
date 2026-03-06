// [APPLE-TTP] AppConfig.swift
// Global configuration for Apple entitlement submission.
//
// HOW TO USE:
//   • During Apple TTP approval process: set isAppleApprovalMode = true
//   • Once Apple approves the entitlement: set isAppleApprovalMode = false
//
// When true, the app enforces all Apple UX requirements for Tap to Pay:
//   - Mandatory onboarding (no "Maybe Later" skip)
//   - Official Apple T&C must be accepted before TTP checkout
//   - TTP setup prompt shown at end of new event setup
//   - ProximityReaderDiscovery used for iOS 18+ education
//
// Search for [APPLE-TTP] in commit history to find all related changes.

import Foundation

struct AppConfig {
    /// Controls whether Apple Tap to Pay approval-mode UX is active.
    /// Set to `false` once Apple has approved the TTP entitlement.
    static let isAppleApprovalMode: Bool = true
}
