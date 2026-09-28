import ReliveCore
import SwiftUI

@main
struct ReliveApp: App {
    var body: some Scene {
        WindowGroup {
            Text(MomentTitle(primary: "Relive", secondary: "0.1").combined)
        }
    }
}
