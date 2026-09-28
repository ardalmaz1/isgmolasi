import ReliveCore
import SwiftUI

/// Shows the Memory Engine's real progress. Each message corresponds to the stage actually
/// running — nothing is staged or delayed for effect.
struct ProcessingView: View {
    /// Called once the story is ready (after a short beat so the line can be read).
    var onFinished: () -> Void

    @Environment(StoryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isReady = false
    @State private var lastProgress = MemoryEngineProgress(stage: .readingMetadata)

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Spacer()

            Text(isReady ? "Your story is ready. ❤️" : "Finding your story…")
                .font(Typography.display)
                .foregroundStyle(Palette.textPrimary)
                .contentTransition(.opacity)
                .fixedSize(horizontal: false, vertical: true)

            if case .failed(let message) = store.processing {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text(message)
                        .font(Typography.callout)
                        .foregroundStyle(Palette.textSecondary)
                    Button("Try Again") {
                        Task { await store.process() }
                    }
                    .buttonStyle(.reliveOutline)
                }
            } else if !isReady {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(Self.message(for: lastProgress.stage))
                        .font(Typography.title3)
                        .foregroundStyle(Palette.textSecondary)
                        .id(lastProgress.stage)
                        .transition(.opacity)

                    ProgressView(value: lastProgress.overallFraction)
                        .progressViewStyle(.linear)
                        .tint(Palette.textPrimary)
                        .padding(.top, Spacing.xs)

                    if let detail = Self.detail(for: lastProgress) {
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: lastProgress.stage)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: isReady)
        .task {
            if !store.processing.isRunning {
                await store.process()
            }
        }
        .onChange(of: store.processing, initial: true) { _, state in
            switch state {
            case .running(let progress):
                lastProgress = progress
            case .finished:
                guard !isReady else { return }
                isReady = true
                Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    store.acknowledgeProcessingResult()
                    onFinished()
                }
            default:
                break
            }
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
