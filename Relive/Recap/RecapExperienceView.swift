import os
import ReliveCore
import SwiftUI

/// Monthly Recap 2.0 / Our Year 2.0: a full-screen, paged, editorial recap of a real period.
///
/// Swipe or tap Next through the chapters; nothing advances on its own, the progress is always
/// visible and Close is always one tap away. Free users see the opening chapters, a calm
/// "the rest is Premium" page and the closing card (whose share and create actions follow the
/// existing Premium rules); Premium users see every chapter.
struct RecapExperienceView: View {
    let request: RecapRequest

    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @Environment(PremiumStore.self) private var premium
    @Environment(MadeForYouStore.self) private var madeForYou
    @Environment(\.analytics) private var analytics
    @Environment(\.photoImageLoader) private var loader
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var plan: RecapPlan?
    @State private var page = 0
    @State private var gate = PremiumGate()
    @State private var export = ExportController()
    @State private var completed = false

    /// Free users see this many chapters after the opening before the Premium page.
    static let freePreviewChapters = 2

    private var capability: PremiumCapability {
        request.period.isYearPeriod ? .fullYearInReview : .fullMonthlyRecap
    }

    private var entry: PaywallEntryPoint {
        request.period.isYearPeriod ? .ourYear : .monthlyRecap
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            if let plan {
                let pages = Self.pages(for: plan, isFull: premium.hasAccess(to: capability))
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        RecapPageView(page: page, plan: plan, actions: actions)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: page)
                .safeAreaInset(edge: .top) { header(count: pages.count) }
                .safeAreaInset(edge: .bottom) { footer(count: pages.count) }
                .onChange(of: page) { _, index in
                    guard pages.indices.contains(index) else { return }
                    analytics.track(.recapChapterViewed, ["period": request.period.kindCode, "chapter": pages[index].code, "index": String(index)])
                    if index == pages.count - 1, !completed {
                        completed = true
                        analytics.track(.recapCompleted, ["period": request.period.kindCode, "chapters": String(pages.count)])
                    }
                }
            } else {
                ProgressView()
                    .accessibilityLabel("Preparing the recap")
                    .safeAreaInset(edge: .top) { header(count: 0) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .premiumPaywall(gate)
        .onAppear {
            #if DEBUG
            Logger(subsystem: "app.relive", category: "intelligence").notice("recap_presented origin=\(request.origin, privacy: .public)")
            #endif
        }
        .task { await load() }
    }

    // MARK: - Chrome

    private func header(count: Int) -> some View {
        HStack(spacing: Spacing.m) {
            // One segment per page: where you are, and how much there is.
            HStack(spacing: 4) {
                ForEach(0..<max(count, 0), id: \.self) { index in
                    Capsule()
                        .fill(index <= page ? Palette.textPrimary : Palette.hairline)
                        .frame(height: 3)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Chapter \(page + 1) of \(count)")
            .accessibilityIdentifier("recapProgress")
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Palette.surface))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("recapClose")
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.xs)
    }

    private func footer(count: Int) -> some View {
        HStack {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut) { page = max(0, page - 1) }
            } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .disabled(page == 0)
            .opacity(page == 0 ? 0 : 1)
            .accessibilityLabel("Previous chapter")
            .accessibilityIdentifier("recapPrevious")
            Spacer()
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut) { page = min(count - 1, page + 1) }
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
                    .font(Typography.callout.weight(.semibold))
                    .frame(minHeight: 44)
                    .padding(.horizontal, Spacing.m)
            }
            .disabled(page >= count - 1)
            .opacity(page >= count - 1 ? 0 : 1)
            .accessibilityLabel("Next chapter")
            .accessibilityIdentifier("recapNext")
        }
        .foregroundStyle(Palette.textPrimary)
        .padding(.horizontal, Spacing.s)
        .background(Palette.background.opacity(0.92))
    }

    // MARK: - Pages

    /// What a page shows: a chapter, or the calm "the rest is Premium" page.
    enum Page: Hashable {
        case chapter(RecapChapter)
        case premium

        var code: String {
            switch self {
            case .chapter(let chapter): chapter.kind.rawValue
            case .premium: "premium"
            }
        }
    }

    /// Everything for Premium (and for compact recaps, which hold nothing Premium); otherwise
    /// the opening, a short preview, the Premium page and the closing.
    static func pages(for plan: RecapPlan, isFull: Bool) -> [Page] {
        let chapters = plan.chapters
        guard plan.isRich, !isFull else { return chapters.map(Page.chapter) }
        let closing = chapters.last { $0.kind == .closing }
        let body = chapters.filter { $0.kind != .closing }
        let preview = Array(body.prefix(1 + freePreviewChapters))
        guard body.count > preview.count else { return chapters.map(Page.chapter) }
        return preview.map(Page.chapter) + [.premium] + (closing.map { [.chapter($0)] } ?? [])
    }

    private var actions: RecapActions {
        RecapActions(
            seeAll: { gate.showPaywall(entry, premium: premium, heroAssetID: plan?.chapters.first?.hero) },
            create: { kind in create(kind) },
            share: { Task { await share() } },
            openMoment: { _ in },
            export: export,
            periodName: periodName
        )
    }

    private var periodName: String {
        switch request.period {
        case .month(let month): CreationText.monthName(month) ?? CreationText.monthTitle(month)
        case .year(let year): String(year)
        }
    }

    // MARK: - Actions

    /// Plans once per presentation, off the main thread (metadata only, never pixels), so the
    /// recap — and its Close button — appear at once even for a large library.
    private func load() async {
        guard plan == nil else { return }
        let planner = RecapStoryPlanner(library: store.creationLibrary)
        let period = request.period
        let started = Date()
        let planned = await Task.detached(priority: .userInitiated) { planner.plan(period) }.value
        plan = planned
        analytics.track(.recapOpened, ["kind": request.period.kindCode, "experience": "immersive", "rich": planned.isRich ? "true" : "false", "origin": request.origin])
        #if DEBUG
        let milliseconds = Int(Date().timeIntervalSince(started) * 1000)
        Logger(subsystem: "app.relive", category: "intelligence").notice("\(planned.diagnosticsLine, privacy: .public) ms=\(milliseconds, privacy: .public)")
        #endif
    }

    /// Create from the recap: the period itself as the source, so the photos are Memory
    /// Intelligence's. Part of the full recap (existing Commercial v1 rule).
    private func create(_ kind: CreationKind) {
        guard let plan else { return }
        guard premium.hasAccess(to: capability) else {
            gate.showPaywall(entry, premium: premium, heroAssetID: plan.chapters.first?.hero)
            return
        }
        analytics.track(.recapCreationStarted, ["period": request.period.kindCode, "kind": kind.rawValue])
        app.startCreationFromRecap(kind, source: plan.creationSource)
    }

    /// The closing card as an image: the existing summary card, the existing export, the
    /// existing gate (sharing the recap card is Premium, as before).
    private func share() async {
        guard let plan else { return }
        let library = store.creationLibrary
        let source = CreationImageSource(loader: loader)
        let closing = plan.chapters.last { $0.kind == .closing } ?? plan.chapters.first
        let title: String = switch request.period {
        case .month(let month): CreationText.monthName(month) ?? CreationText.monthTitle(month)
        case .year(let year): "Our \(year)"
        }
        let eyebrow: String = switch request.period {
        case .month(let month): String(month.year)
        case .year: app.coupleName
        }
        analytics.track(.recapShareStarted, ["period": request.period.kindCode])
        await gate.export(capability, entry: entry, premium: premium, heroAssetID: plan.sharePhotos.first) { succeeded in
            await export.share(name: title, analytics: analytics, properties: ["kind": request.period.isYearPeriod ? "our_year" : "monthly_recap"], onShared: {
                succeeded()
                analytics.track(.recapShareCompleted, ["period": request.period.kindCode])
                madeForYou.recordMade(source: plan.creationSource)
            }) {
                let image = try await SummaryCardExport.render(
                    eyebrow: eyebrow,
                    title: title,
                    counts: closing?.text.detail ?? "",
                    photoIDs: plan.sharePhotos,
                    library: library,
                    images: source
                )
                return [image]
            }
        }
    }
}

/// Opens the immersive recap from the scrolling recap screens. Free users can play it too: the
/// preview and the Premium page live inside it. Hidden for the UI tests that predate it
/// (`-ReliveUITestHideMadeForYou`, DEBUG only), so their layouts stay the same.
struct RecapPlayButton: View {
    let title: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        if !Self.isHidden {
            Button(action: action) {
                Label(title, systemImage: "play.fill")
            }
            .buttonStyle(.relivePrimary)
            .accessibilityHint("Opens the recap, chapter by chapter")
            .accessibilityIdentifier(identifier)
        }
    }

    private static var isHidden: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ReliveUITestHideMadeForYou")
        #else
        false
        #endif
    }
}

/// What a page can do.
struct RecapActions {
    let seeAll: () -> Void
    let create: (CreationKind) -> Void
    let share: () -> Void
    let openMoment: (MomentID) -> Void
    let export: ExportController
    let periodName: String
}

extension RecapPeriod {
    var isYearPeriod: Bool {
        if case .year = self { return true }
        return false
    }

    var kindCode: String { isYearPeriod ? "year" : "month" }
}
