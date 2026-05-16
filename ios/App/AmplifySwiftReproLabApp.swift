import Amplify
import AWSCognitoAuthPlugin
import AWSAPIPlugin
import SwiftUI

@main
struct AmplifySwiftReproLabApp: App {
    @StateObject private var store = SubscriptionProbeStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            Amplify.Logging.logLevel = .verbose
            try Amplify.add(plugin: AWSCognitoAuthPlugin())
            try Amplify.add(plugin: AWSAPIPlugin())
            try Amplify.configure(with: .amplifyOutputs)
        } catch {
            assertionFailure("Failed to configure Amplify: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task { @MainActor in
                await store.handleScenePhase(newPhase)
            }
        }
    }
}
