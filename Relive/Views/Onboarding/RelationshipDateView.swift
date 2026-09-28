import ReliveCore
import SwiftUI

struct RelationshipDateView: View {
    @Environment(AppModel.self) private var app
    @State private var draft = RelationshipDateDraft()

    var body: some View {
        OnboardingScaffold(onBack: { app.advance(to: .partner) }) {
            Text("When did your story begin?")
                .font(Typography.display)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            RelationshipDatePicker(draft: $draft)
                .padding(.top, Spacing.s)

            Text("Not sure? An estimate is perfectly fine.")
                .font(Typography.footnote)
                .foregroundStyle(Palette.textSecondary)
        } footer: {
            Button("Continue") {
                app.setRelationshipStart(draft.start)
                app.advance(to: .photos)
            }
            .buttonStyle(.relivePrimary)
        }
        .onAppear {
            if let start = app.relationship?.start {
                draft = RelationshipDateDraft(start: start)
            }
        }
    }
}

/// Editable relationship start: month + year by default, an exact day when the user knows it.
struct RelationshipDateDraft: Equatable {
    var month: Int
    var year: Int
    var exactDate: Date
    var knowsExactDay: Bool

    init(now: Date = Date(), calendar: Calendar = .current) {
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        month = calendar.component(.month, from: oneYearAgo)
        year = calendar.component(.year, from: oneYearAgo)
        exactDate = oneYearAgo
        knowsExactDay = false
    }

    init(start: RelationshipStart, calendar: Calendar = .current) {
        month = calendar.component(.month, from: start.date)
        year = calendar.component(.year, from: start.date)
        exactDate = start.date
        knowsExactDay = start.precision == .day
    }

    /// Never in the future.
    func makeStart(now: Date = Date(), calendar: Calendar = .current) -> RelationshipStart {
        if knowsExactDay {
            return RelationshipStart(date: min(exactDate, now), precision: .day)
        }
        let components = DateComponents(year: year, month: month, day: 1)
        let date = calendar.date(from: components) ?? now
        return RelationshipStart(date: min(date, now), precision: .month)
    }

    var start: RelationshipStart { makeStart() }
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
            } else {
                HStack(spacing: 0) {
                    Picker("Month", selection: $draft.month) {
                        ForEach(1...12, id: \.self) { month in
                            Text(calendar.monthSymbols[month - 1]).tag(month)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()

                    Picker("Year", selection: $draft.year) {
                        ForEach(years, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    .clipped()
                }
            }

            Button(draft.knowsExactDay ? "I only remember the month" : "I know the exact day") {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if draft.knowsExactDay {
                        draft.month = calendar.component(.month, from: draft.exactDate)
                        draft.year = calendar.component(.year, from: draft.exactDate)
                    } else {
                        draft.exactDate = calendar.date(from: DateComponents(year: draft.year, month: draft.month, day: 1)) ?? draft.exactDate
                    }
                    draft.knowsExactDay.toggle()
                }
            }
            .buttonStyle(.reliveQuiet)
        }
    }
}
