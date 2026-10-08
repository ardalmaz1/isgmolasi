import ReliveCore
import SwiftUI

/// The one paywall. Shown only after the user has seen what Relive made — never at launch or
/// after onboarding. No countdowns, no urgency, and the close button is always visible.
struct PaywallView: View {
    let entry: PaywallEntryPoint
    var heroAssetID: AssetID?
    let onClose: () -> Void

    @Environment(PremiumStore.self) private var premium
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var selected: PremiumProductRole = .annual
    @State private var showsPrivacy = false

    private var copy: PaywallCopy { PaywallCopy(entry: entry) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header
                benefits
                if premium.isPremium {
                    alreadyPremium
                } else {
                    plans
                    purchaseButton
                    messages
                }
                footer
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.xxl)
            .padding(.bottom, Spacing.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .reliveBackground()
        .overlay(alignment: .topTrailing) { closeButton }
        .sheet(isPresented: $showsPrivacy) { PrivacySummaryView() }
        .accessibilityIdentifier("paywall")
        .onAppear {
            premium.trackPaywall(viewed: entry)
            premium.clearPurchaseMessage()
            premium.clearRestoreMessage()
            if premium.productsState != .loaded { Task { await premium.loadProducts() } }
        }
        .onDisappear { premium.trackPaywall(closed: entry) }
        .onChange(of: premium.isPremium) { _, isPremium in
            // Purchased, restored, or approved while open: done.
            if isPremium { onClose() }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: premium.productsState)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selected)
    }

    // MARK: - Pieces

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Palette.surface))
        }
        .buttonStyle(.plain)
        .padding(.trailing, Spacing.m)
        .padding(.top, Spacing.s)
        .accessibilityLabel("Close")
        .accessibilityIdentifier("paywallClose")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let heroAssetID {
                // A photo from what the user was making — shown only on this iPhone.
                Color.clear
                    .frame(width: 88, height: 110)
                    .overlay { AssetImageView(assetID: heroAssetID) }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    .accessibilityHidden(true)
                    .padding(.bottom, Spacing.xs)
            }
            if let context = copy.context {
                Text(context).eyebrowStyle()
                    .accessibilityIdentifier("paywallContext")
            }
            Text(copy.title)
                .font(Typography.display)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(copy.message)
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.trailing, Spacing.xxl)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ForEach(copy.benefits, id: \.self) { benefit in
                Label {
                    Text(benefit)
                        .font(Typography.body)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Premium includes: " + copy.benefits.joined(separator: ", "))
    }

    @ViewBuilder
    private var plans: some View {
        switch premium.productsState {
        case .idle, .loading:
            HStack(spacing: Spacing.s) {
                ProgressView()
                Text("Loading prices…")
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("paywallLoading")
        case .failed(let message):
            VStack(spacing: Spacing.s) {
                Text(message)
                    .font(Typography.callout)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again") { Task { await premium.loadProducts() } }
                    .buttonStyle(.reliveOutline)
                    .accessibilityIdentifier("paywallRetry")
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .accessibilityIdentifier("paywallPricesFailed")
        case .loaded:
            VStack(spacing: Spacing.s) {
                if let annual = premium.annual {
                    PlanRow(product: annual, isSelected: selected == .annual, isRecommended: true) { selected = .annual }
                }
                if let monthly = premium.monthly {
                    PlanRow(product: monthly, isSelected: selected == .monthly, isRecommended: false) { selected = .monthly }
                }
            }
            .onAppear {
                if premium.annual == nil, premium.monthly != nil { selected = .monthly }
            }
        }
    }

    private var selectedProduct: PremiumProduct? {
        premium.products.first { $0.role == selected }
    }

    private var isPurchasing: Bool {
        if case .purchasing = premium.purchaseState { return true }
        return false
    }

    private var purchaseButton: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Button {
                Task { await premium.purchase(selected, entry: entry) }
            } label: {
                if isPurchasing {
                    ProgressView().tint(Palette.onPrimary)
                } else {
                    Text(PaywallText.callToAction(selectedProduct))
                }
            }
            .buttonStyle(.relivePrimary)
            .disabled(selectedProduct == nil || isPurchasing)
            .accessibilityLabel(isPurchasing ? "Purchasing" : PaywallText.callToAction(selectedProduct))
            .accessibilityIdentifier("paywallPurchase")

            if let product = selectedProduct {
                Text(PaywallText.disclosure(product))
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("paywallDisclosure")
            }
        }
    }

    @ViewBuilder
    private var messages: some View {
        let text: String? = switch premium.purchaseState {
        case .pending: "Your purchase is waiting for approval. Premium turns on as soon as it’s approved."
        case .failed(let message): message
        case .idle, .purchasing: nil
        }
        if let text {
            Text(text)
                .font(Typography.callout)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("paywallMessage")
        }
        RestoreStatusText()
    }

    private var alreadyPremium: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("You have Relive Premium.")
                .font(Typography.title3)
                .foregroundStyle(Palette.textPrimary)
            Button("Done", action: onClose)
                .buttonStyle(.relivePrimary)
        }
    }

    private var footer: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Spacing.m))
        return layout {
            Button("Restore Purchases") { Task { await premium.restore(entry: entry) } }
                .disabled(premium.restoreState == .restoring)
                .accessibilityIdentifier("paywallRestore")
            Button("Terms") { openURL(CommercialLinks.termsOfUse) }
                .accessibilityLabel("Terms of Use")
                .accessibilityIdentifier("paywallTerms")
            Button("Privacy") {
                if let url = CommercialLinks.privacyPolicy { openURL(url) } else { showsPrivacy = true }
            }
            .accessibilityLabel("Privacy Policy")
            .accessibilityIdentifier("paywallPrivacy")
        }
        .buttonStyle(.reliveQuiet)
        .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center)
    }
}

/// One plan. Annual is recommended visually; Monthly stays a clear, equal choice.
private struct PlanRow: View {
    let product: PremiumProduct
    let isSelected: Bool
    let isRecommended: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Spacing.m) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Palette.accent : Palette.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.xs) {
                        Text(PaywallText.planName(product.role))
                            .font(Typography.title3)
                            .foregroundStyle(Palette.textPrimary)
                        if isRecommended {
                            Text("Recommended")
                                .font(Typography.eyebrow)
                                .foregroundStyle(Palette.onPrimary)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Palette.textPrimary))
                        }
                    }
                    Text(PaywallText.priceLine(product))
                        .font(Typography.callout)
                        .foregroundStyle(Palette.textSecondary)
                    if let badge = PaywallText.offerBadge(product) {
                        Text(badge)
                            .font(Typography.footnote.weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(isSelected ? Palette.surface : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Palette.textPrimary : Palette.hairline, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(product.role == .annual ? "paywallPlanAnnual" : "paywallPlanMonthly")
    }

    private var accessibilityText: String {
        var parts = [PaywallText.planName(product.role), "\(product.displayPrice) per \(product.period.recurringPhrase)"]
        if let badge = PaywallText.offerBadge(product) { parts.append(badge) }
        if isRecommended { parts.append("Recommended") }
        return parts.joined(separator: ", ")
    }
}

/// What Restore Purchases found, in plain words. Never claims success it didn't have.
struct RestoreStatusText: View {
    @Environment(PremiumStore.self) private var premium

    var body: some View {
        let text: String? = switch premium.restoreState {
        case .idle: nil
        case .restoring: "Checking with the App Store…"
        case .restored: "Your Premium subscription is active again."
        case .nothingToRestore: "No active Premium subscription was found for this Apple Account."
        case .failed(let message): message
        }
        if let text {
            Text(text)
                .font(Typography.callout)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("restoreMessage")
        }
    }
}

/// Relive's privacy in a few true sentences, used until a privacy policy URL is configured.
struct PrivacySummaryView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text("Your photos stay on this iPhone and are organized on-device. Nothing is uploaded and there is no account. To name places, Relive asks Apple’s location service about a location — never a photo.")
                    Text("Subscriptions are handled by Apple. Relive never sees your payment details; it only learns from the App Store whether Premium is active.")
                    Text("Relive logs a few anonymous product events on this iPhone only (for example, that the paywall was opened). They never include photos, names, notes, captions or places.")
                }
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .padding(Spacing.screenMargin)
            }
            .reliveBackground()
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
