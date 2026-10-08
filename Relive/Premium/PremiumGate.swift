import Observation
import ReliveCore
import SwiftUI

/// Why the paywall is open, and (optionally) a photo from what the user was making.
struct PaywallRequest: Identifiable, Equatable {
    let id = UUID()
    let entry: PaywallEntryPoint
    var heroAssetID: AssetID?
}

/// One per screen that keeps creations. Asks `PremiumStore` before an export, shows the shared
/// paywall when Premium is needed, and — if the user subscribes there — finishes what they were
/// doing once the paywall closes. Previews never come through here.
@Observable
@MainActor
final class PremiumGate {
    var request: PaywallRequest?
    @ObservationIgnored private var pending: (@MainActor () async -> Void)?

    /// Runs `perform` if the user may keep this creation now. `perform` receives a callback to
    /// call only when the save or share actually succeeded; that is what uses the free creation.
    func export(
        _ capability: PremiumCapability,
        entry: PaywallEntryPoint,
        premium: PremiumStore,
        heroAssetID: AssetID? = nil,
        perform: @escaping @MainActor (_ succeeded: @escaping @MainActor () -> Void) async -> Void
    ) async {
        let decision = await premium.exportDecision(for: capability)
        switch decision {
        case .allowed, .allowedAsFreeCreation:
            await perform { premium.recordSuccessfulExport(of: capability, decision: decision) }
        case .requiresPremium:
            premium.trackPremiumFeatureTapped(entry)
            pending = { await perform {} }
            request = PaywallRequest(entry: entry, heroAssetID: heroAssetID)
        }
    }

    /// Shows the paywall for something that isn't an export (the full recap).
    func showPaywall(_ entry: PaywallEntryPoint, premium: PremiumStore, heroAssetID: AssetID? = nil) {
        premium.trackPremiumFeatureTapped(entry)
        pending = nil
        request = PaywallRequest(entry: entry, heroAssetID: heroAssetID)
    }

    /// The paywall closed: continue only if the user is now Premium.
    func paywallDismissed(premium: PremiumStore) {
        let action = pending
        pending = nil
        guard premium.isPremium, let action else { return }
        Task { await action() }
    }
}

extension View {
    /// Presents the shared paywall for `gate`.
    func premiumPaywall(_ gate: PremiumGate) -> some View {
        modifier(PremiumPaywallModifier(gate: gate))
    }
}

private struct PremiumPaywallModifier: ViewModifier {
    @Bindable var gate: PremiumGate
    @Environment(PremiumStore.self) private var premium

    func body(content: Content) -> some View {
        content.sheet(item: $gate.request, onDismiss: { gate.paywallDismissed(premium: premium) }) { request in
            PaywallView(entry: request.entry, heroAssetID: request.heroAssetID) {
                gate.request = nil
            }
        }
    }
}

/// A small, quiet "Premium" marker: this creates more, it doesn't block.
struct PremiumBadge: View {
    var body: some View {
        Label("Premium", systemImage: "sparkles")
            .labelStyle(.titleAndIcon)
            .font(Typography.eyebrow)
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 3)
            .background(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
            .accessibilityLabel("Premium")
    }
}

/// Where the paywall's Terms and Privacy go. Terms default to Apple's standard licence
/// agreement; the privacy policy URL must be set before release (see docs/COMMERCIAL.md).
enum CommercialLinks {
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    /// Set to the published privacy policy before App Store submission. Until then Relive shows
    /// its on-device privacy summary.
    static let privacyPolicy: URL? = nil
}

/// Where a free preview ends: says what the full version holds, calmly, with one way in.
struct PremiumTeaser: View {
    let title: String
    let message: String
    let actionTitle: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            PremiumBadge()
            Text(title)
                .font(Typography.title2)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(Typography.callout)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: action)
                .buttonStyle(.relivePrimary)
                .accessibilityIdentifier(identifier)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.surface))
    }
}
