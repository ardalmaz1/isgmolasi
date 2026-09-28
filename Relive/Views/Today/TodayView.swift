import ReliveCore
import SwiftUI

/// Today: one rediscovered memory, a way back into the story, and a way to add more.
struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(StoryStore.self) private var store
    @State private var path: [MomentRoute] = []
    @State private var isAddingMemories = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(DateText.todayHeader(Date()))
                            .eyebrowStyle()
                        Text("Today")
                            .font(Typography.display)
                            .foregroundStyle(Palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .padding(.top, Spacing.l)

                    if app.shouldAskSmileQuestion {
                        SmileQuestionCard()
                    }

                    if let memory = app.foundMemory {
                        FoundForYouCard(memory: memory) {
                            app.openFoundMemory()
                            path.append(MomentRoute(momentID: memory.momentID, source: "found_for_you"))
                        }
                    } else if store.hasStory {
                        QuietMessageView(
                            title: "Nothing to resurface yet",
                            message: "As your story grows older, Relive will bring back memories here."
                        )
                    }

                    if let next = app.nextMomentToContinue {
                        ContinueStoryCard(moment: next) {
                            app.continueStory()
                        }
                    }

                    AddMemoriesCard {
                        isAddingMemories = true
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .reliveBackground()
            .statusBarBackdrop()
            .toolbar(.hidden, for: .navigationBar)
            .momentDestination()
        }
        .addMemoriesFlow(isPresented: $isAddingMemories)
        .onAppear { app.refreshFoundMemory() }
        .onChange(of: store.story.generatedAt) { _, _ in app.refreshFoundMemory() }
    }
}

/// "Found for you ❤️" — the photo carries the emotion; the words stay out of the way.
struct FoundForYouCard: View {
    let memory: FoundMemory
    let onOpen: () -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text("Found for you ❤️")
                    .eyebrowStyle()
                Spacer()
                Menu {
                    Button {
                        withAnimation { app.dontShowFoundMemoryAgain() }
                    } label: {
                        Label("Don’t Show This Again", systemImage: "eye.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 44, height: 32, alignment: .trailing)
                }
                .accessibilityLabel("Options")
            }

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    FramedAssetImage(assetID: memory.assetID, aspectRatio: 4 / 5)
                    Text(caption)
                        .font(Typography.title3)
                        .foregroundStyle(Palette.textPrimary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Found for you: \(caption)")
            .accessibilityHint("Opens the memory")
        }
    }

    /// "2 years ago · Kaş"
    private var caption: String {
        [memory.ageDescription, memory.place?.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Picks the story up where the user left it.
struct ContinueStoryCard: View {
    let moment: Moment
    let onContinue: () -> Void

    @Environment(StoryStore.self) private var store

    var body: some View {
        Button(action: onContinue) {
            HStack(spacing: Spacing.m) {
                Color.clear
                    .frame(width: 72, height: 90)
                    .overlay { AssetImageView(assetID: store.heroAssetID(for: moment)) }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.photo, style: .continuous))

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Continue your story")
                        .eyebrowStyle()
                    Text(moment.title.primary)
                        .font(Typography.title3)
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let range = DateText.range(start: moment.startDate, end: moment.endDate, includeYear: true) {
                        Text(range)
                            .font(Typography.footnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.m)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

struct AddMemoriesCard: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Found more photos of the two of you?")
                .font(Typography.title3)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Add them and Relive will place them in your story.")
                .font(Typography.callout)
                .foregroundStyle(Palette.textSecondary)
            Button("Add Memories", action: onAdd)
                .buttonStyle(.reliveOutline)
                .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }
}

/// Prototype 0.1's key validation signal. Asked once, answered once.
struct SmileQuestionCard: View {
    @Environment(AppModel.self) private var app
    @State private var answered: SmileResponse?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if let answered {
                Text(answered == .yes ? "That’s what it’s for. Thank you." : "Thank you. There’s more to find as your story grows.")
                    .font(Typography.bodySerif)
                    .foregroundStyle(Palette.textPrimary)
            } else {
                Text("Did you find something that made you smile?")
                    .font(Typography.title3)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.s) {
                    Button("Yes") { answer(.yes) }
                        .buttonStyle(.relivePrimary)
                    Button("Not yet") { answer(.notYet) }
                        .buttonStyle(.reliveOutline)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func answer(_ response: SmileResponse) {
        withAnimation(.easeInOut(duration: 0.3)) {
            answered = response
        }
        // Record after the thank-you is visible, so the card doesn't vanish mid-tap.
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { app.answerSmileQuestion(response) }
        }
    }
}
