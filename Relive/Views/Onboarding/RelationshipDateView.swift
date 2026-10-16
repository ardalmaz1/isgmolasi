import ReliveCore
import SwiftUI

struct RelationshipDateView: View {
    @Environment(AppModel.self) private var app
    @State private var draft = RelationshipDateDraft()
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        OnboardingScaffold(onBack: { app.advance(to: .partner) }) {
            Text("When did your story begin?")
                .font(Typography.display)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            RelationshipDatePicker(draft: $draft)
                .padding(.top, Spacing.s)

            Text("Choose a month and a year — an estimate is perfectly fine. You can change it later in Us.")
                .font(Typography.footnote)
                .foregroundStyle(Palette.textSecondary)
            // At the largest text sizes the footer keeps only the main action.
            if typeSize.isAccessibilitySize {
                skipButton
                    .padding(.top, Spacing.s)
            }
        } footer: {
            Button("Continue") {
                // Only a date the couple chose is ever saved.
                guard let start = draft.start else { return }
                app.setRelationshipStart(start)
                app.advance(to: .chooseStart)
            }
            .buttonStyle(.relivePrimary)
            .disabled(!draft.isComplete)
            .accessibilityHint(draft.isComplete ? "" : "Choose a month and a year, or skip")
            .accessibilityIdentifier("startDateContinue")
            if !typeSize.isAccessibilitySize {
                skipButton
            }
        }
        .onAppear {
            if let start = app.relationship?.start {
                draft = RelationshipDateDraft(start: start)
            }
        }
    }

    private var skipButton: some View {
        Button("I’m not sure — skip") {
            app.skipRelationshipStart()
            app.advance(to: .chooseStart)
        }
        .buttonStyle(.reliveQuiet)
        .accessibilityHint("Relive won’t count days together until you add a date in Us")
        .accessibilityIdentifier("startDateSkip")
    }
}

/// Editable relationship start: month + year by default, an exact day when the user knows it.
///
/// Nothing is selected until the couple chooses it: a new draft has no month, no year and no
/// day, so `start` is `nil` and Continue stays disabled. Relive never proposes a date (no "one
/// year ago" default) — an untouched screen can only lead to "I'm not sure — skip".
struct RelationshipDateDraft: Equatable {
    /// `nil` until chosen.
    var month: Int?
    var year: Int?
    /// The calendar's displayed day in exact-day mode; only counts once `exactDayChosen`.
    var exactDate: Date
    var knowsExactDay: Bool
    /// The couple tapped a day in the calendar (the calendar shows one before that).
    var exactDayChosen: Bool

    /// Nothing chosen.
    init(now: Date = Date()) {
        month = nil
        year = nil
        exactDate = now
        knowsExactDay = false
        exactDayChosen = false
    }

    /// The couple's saved date, to edit.
    init(start: RelationshipStart, calendar: Calendar = .current) {
        month = calendar.component(.month, from: start.date)
        year = calendar.component(.year, from: start.date)
        exactDate = start.date
        knowsExactDay = start.precision == .day
        exactDayChosen = start.precision == .day
    }

    /// The chosen start, never in the future; `nil` while nothing (or only half) is chosen.
    func makeStart(now: Date = Date(), calendar: Calendar = .current) -> RelationshipStart? {
        if knowsExactDay {
            return exactDayChosen ? RelationshipStart(date: min(exactDate, now), precision: .day) : nil
        }
        guard let month, let year else { return nil }
        let components = DateComponents(year: year, month: month, day: 1)
        let date = calendar.date(from: components) ?? now
        return RelationshipStart(date: min(date, now), precision: .month)
    }

    var start: RelationshipStart? { makeStart() }
    var isComplete: Bool { start != nil }
}

/// Month/year wheels, or a calendar for an exact day.
struct RelationshipDatePicker: View {
    @Binding var draft: RelationshipDateDraft

    private let calendar = Calendar.current
    private var currentYear: Int { calendar.component(.year, from: Date()) }
    private var years: [Int] { Array(stride(from: currentYear, through: currentYear - 70, by: -1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if draft.knowsExactDay {
                DatePicker("Start date", selection: $draft.exactDate, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    // Only a day the couple taps counts.
                    .onChange(of: draft.exactDate) { _, _ in draft.exactDayChosen = true }
            } else {
                HStack(spacing: 0) {
                    Picker("Month", selection: $draft.month) {
                        Text("Month").tag(Int?.none)
                        ForEach(1...12, id: \.self) { month in
                            Text(calendar.monthSymbols[month - 1]).tag(Int?.some(month))
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .accessibilityIdentifier("startMonth")

                    Picker("Year", selection: $draft.year) {
                        Text("Year").tag(Int?.none)
                        ForEach(years, id: \.self) { year in
                            Text(String(year)).tag(Int?.some(year))
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .accessibilityIdentifier("startYear")
                }
            }

            Button(draft.knowsExactDay ? "I only remember the month" : "I know the exact day") {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if draft.knowsExactDay {
                        // Back to month and year: keep only what was actually chosen.
                        if draft.exactDayChosen {
                            draft.month = calendar.component(.month, from: draft.exactDate)
                            draft.year = calendar.component(.year, from: draft.exactDate)
                        }
                    } else if let month = draft.month, let year = draft.year {
                        // Show the chosen month; a day still has to be tapped.
                        draft.exactDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? draft.exactDate
                    }
                    draft.exactDayChosen = false
                    draft.knowsExactDay.toggle()
                }
            }
            .buttonStyle(.reliveQuiet)
        }
    }
}
