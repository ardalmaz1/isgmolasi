import ReliveCore
import SwiftUI

/// "Arda ♥ Kübra" — the couple's names joined by a quiet heart in the secondary ink, read by
/// VoiceOver as "Arda and Kübra". The one way Relive shows the two names together on screen.
struct CoupleNameText: View {
    let name: CoupleName

    var body: some View {
        Group {
            if name.partnerName.isEmpty {
                Text(name.lead())
            } else {
                Text("\(Text(name.lead())) \(Text(CoupleName.heart).foregroundStyle(Palette.textSecondary)) \(Text(name.partnerName))")
            }
        }
        .accessibilityLabel(name.spoken())
    }
}

extension AppModel {
    /// The couple's names; nil before onboarding has a partner name.
    var couple: CoupleName? {
        relationship.map(\.coupleName).flatMap { $0.partnerName.isEmpty ? nil : $0 }
    }

    /// "Arda and Kübra" — for accessibility labels where the names appear in a plain string.
    var coupleSpokenName: String {
        couple?.spoken() ?? coupleName
    }
}

/// The couple's names as a title — "Arda ♥ Kübra" — or "Your story" before there is a partner
/// name. Style it like any text (`.font`, `.foregroundStyle`).
struct CoupleTitle: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let couple = app.couple {
            CoupleNameText(name: couple)
        } else {
            Text(app.coupleName)
        }
    }
}
