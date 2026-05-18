import SwiftUI

@main
struct KikuApp: App {
    @StateObject private var profileStore = ProfileStore()

    var body: some Scene {
        WindowGroup {
            if profileStore.isSetupComplete {
                ContentView()
                    .environmentObject(profileStore)
            } else {
                ProfileSetupView(store: profileStore)
            }
        }
    }
}
