import ReliveCore
import SwiftUI

/// Moments the user chose to hide. Nothing here is ever resurfaced.
struct HiddenMemoriesView: View {
    @Environment(StoryStore.self) private var store

    var body: some View {
        Group {
            if store.hiddenMoments.isEmpty {
                QuietMessageView(
                    title: "No hidden memories",
                    message: "Memories you hide won’t appear in your story or be resurfaced."
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(store.hiddenMoments) { moment in
                            HStack(spacing: Spacing.m) {
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(moment.title.primary)
                                        .font(Typography.body)
                                        .foregroundStyle(Palette.textPrimary)
                                    if let range = DateText.range(start: moment.startDate, end: moment.endDate, includeYear: true) {
                                        Text(range)
                                            .font(Typography.footnote)
                                            .foregroundStyle(Palette.textSecondary)
                                    }
                                }
                                Spacer()
                                Button("Show") {
                                    withAnimation { store.setHidden(false, for: moment.id) }
                                }
                                .buttonStyle(.borderless)
                                .font(Typography.callout.weight(.semibold))
                            }
                        }
                    } footer: {
                        Text("Photos aren’t shown here on purpose. Choose Show to return a memory to your story.")
                    }
                    .listRowBackground(Palette.surface)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .reliveBackground()
        .navigationTitle("Hidden Memories")
        .navigationBarTitleDisplayMode(.inline)
    }
}
