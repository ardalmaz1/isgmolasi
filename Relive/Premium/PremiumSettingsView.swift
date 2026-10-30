import ReliveCore
import StoreKit
import SwiftUI

/// Us → Relive Premium: what you have, Restore Purchases, and managing the subscription.
struct PremiumSettingsView: View {
    @Environment(PremiumStore.self) private var premium
    @State private var gate = PremiumGate()
    @State private var managesSubscription = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .font(Typography.title3)
                        .foregroundStyle(Palette.textPrimary)
                    Text(detail)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Spacing.xxs)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("premiumStatus")

                if premium.isPremium {
                    Button("Manage Subscription") { managesSubscription = true }
                        .accessibilityIdentifier("premiumManage")
                } else {
                    Button("See Yuvi Premium") { gate.showPaywall(.settings, premium: premium) }
                        .accessibilityIdentifier("premiumSee")
                }
            } footer: {
                Text("Your memories, moments, places, notes and favorites are always free. Premium is for what Yuvi creates from them.")
            }
            .listRowBackground(Palette.surface)

            Section {
                Button("Restore Purchases") { Task { await premium.restore(entry: .settings) } }
                    .disabled(premium.restoreState == .restoring)
                    .accessibilityIdentifier("settingsRestore")
                RestoreStatusText()
            } footer: {
                Text("Subscribed on another iPhone or after reinstalling? Restore checks your Apple Account.")
            }
            .listRowBackground(Palette.surface)

            Section {
                Link("Terms of Use", destination: CommercialLinks.termsOfUse)
                if let privacy = CommercialLinks.privacyPolicy {
                    Link("Privacy Policy", destination: privacy)
                } else {
                    NavigationLink("Privacy") { PrivacySummaryView() }
                }
            }
            .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
        .reliveBackground()
        .navigationTitle("Yuvi Premium")
        .navigationBarTitleDisplayMode(.inline)
        .manageSubscriptionsSheet(isPresented: $managesSubscription)
        .premiumPaywall(gate)
        .task { await premium.refreshEntitlements() }
        .onDisappear { premium.clearRestoreMessage() }
    }

    private var title: String {
        if let grant = premium.status.grant {
            return grant.role == .annual ? String(localized: "Premium · Annual") : String(localized: "Premium · Monthly")
        }
        return premium.status == .unknown ? String(localized: "Checking…") : String(localized: "Yuvi Free")
    }

    private var detail: String {
        switch premium.status {
        case .unknown:
            return String(localized: "Checking your subscription with the App Store.")
        case .premium(let grant):
            if grant.isInGracePeriod {
                return String(localized: "Apple couldn’t renew your subscription. Premium stays on while you update your payment method in Settings.")
            }
            guard let date = grant.expirationDate else { return String(localized: "Premium is active.") }
            let day = date.formatted(date: .long, time: .omitted)
            return grant.willAutoRenew ? String(localized: "Renews on \(day).") : String(localized: "Premium ends on \(day). It won’t renew.")
        case .free(let notice):
            let allowance = premium.allowance.isAvailable
                ? String(localized: "Your first creation to save or share is free.")
                : String(localized: "You’ve used your free creation. Previews and editing stay free.")
            switch notice {
            case .billingRetry?:
                return String(localized: "Apple couldn’t renew your subscription. Update your payment method in Settings to turn Premium back on. ") + allowance
            case .expired?:
                return String(localized: "Your Premium subscription has ended. ") + allowance
            case .revoked?:
                return String(localized: "Your Premium subscription was refunded or revoked. ") + allowance
            case .verificationFailed?, nil:
                return allowance
            }
        }
    }
}
