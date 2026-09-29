import ReliveCore
import SwiftUI

/// Shows the Memory Engine's real progress. Each message corresponds to the stage actually
/// running — nothing is staged or delayed for effect.
///
/// Everything on screen is read straight from `StoryStore.processing`, and leaving the screen is
/// driven by the outcome `process()` returns. Nothing depends on observing a particular state
/// change: SwiftUI may coalesce or skip `onChange` callbacks when a fast run changes state
/// several times in one frame, which once left this screen stuck after processing had finished.
struct ProcessingView: View {
    /// Called exactly once, after a successful run, once "Your story is ready" has been shown.
    var onFinished: () -> Void

    /// How long "Your story is ready." stays up before the reveal. Processing is already complete
    /// at this point — this is reading time for the line, not simulated work.
    static let readyMessageDuration: Duration = .seconds(1.4)

    @Environment(StoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bumped by "Try Again" to start a new run.
    @State private var attempt = 0
    @State private var wasInterrupted = false
    @State private var hasHandedOver = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Spacer()

            Text(isReady ? "Your story is ready. ❤️" : "Finding your story…")
                .font(Typography.display)
                .foregroundStyle(Palette.textPrimary)
                .contentTransition(.opacity)
                .fixedSize(horizontal: false, vertical: true)

            if let failureMessage {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text(failureMessage)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.textSecondary)
                    Button("Try Again") {
                        attempt += 1
                    }
                    .buttonStyle(.reliveOutline)
                }
            } else if !isReady {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(Self.message(for: progress.stage))
                        .font(Typography.title3)
                        .foregroundStyle(Palette.textSecondary)
                        .id(progress.stage)
                        .transition(.opacity)

                    ProgressView(value: progress.overallFraction)
                        .progressViewStyle(.linear)
                        .tint(Palette.textPrimary)
                        .padding(.top, Spacing.xs)

                    if let detail = Self.detail(for: progress) {
                        Text(detail)
                            .font(Typography.footnote.monospacedDigit())
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Spacing.screenMargin)
        .reliveBackground()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: progress.stage)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: isReady)
        .task(id: attempt) {
            await runUntilHandedOver()
        }
    }

    // MARK: - State shown on screen

    private var isReady: Bool {
        if hasHandedOver { return true }
        if case .finished = store.processing { return true }
        return false
    }

    private var progress: MemoryEngineProgress {
        if case .running(let progress) = store.processing { return progress }
        return MemoryEngineProgress(stage: .readingMetadata)
    }

    private var failureMessage: String? {
        if case .failed(let message) = store.processing { return message }
        return wasInterrupted ? "Organizing your photos was interrupted." : nil
    }

    // MARK: - Running

    /// Runs (or joins) processing and hands over exactly once when it succeeds. A failure is
    /// shown from the store's state with Try Again; it can never lead to the reveal.
    private func runUntilHandedOver() async {
        wasInterrupted = false
        let outcome: StoryStore.ProcessingOutcome
        if case .finished(let diagnostics) = store.processing {
            // A run finished while this screen wasn't showing: present it instead of starting over.
            outcome = .finished(diagnostics)
        } else {
            outcome = await store.process()
        }

        switch outcome {
        case .finished:
            try? await Task.sleep(for: Self.readyMessageDuration)
            // If the screen went away meanwhile, the result stays unacknowledged, so the next time
            // it appears it hands over straight away instead of processing again.
            guard !Task.isCancelled, !hasHandedOver else { return }
            hasHandedOver = true
            store.acknowledgeProcessingResult()
            onFinished()
        case .failed:
            break
        case .cancelled:
            wasInterrupted = !Task.isCancelled
        }
    }

    static func message(for stage: MemoryEngineStage) -> String {
        switch stage {
        case .readingMetadata, .analyzingImages: "Looking through your memories…"
        case .findingMoments: "Finding moments you spent together…"
        case .findingPlaces: "Finding places you’ve been…"
        case .choosingFavorites, .finished: "Choosing a few favorites…"
        }
    }

    static func detail(for progress: MemoryEngineProgress) -> String? {
        guard progress.stage == .analyzingImages, progress.totalUnits > 0 else { return nil }
        return "\(progress.completedUnits.formatted()) of \(progress.totalUnits.formatted())"
    }
}

/// Processing as an onboarding step.
struct OnboardingProcessingView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ProcessingView {
            app.advance(to: .reveal)
        }
    }
}
