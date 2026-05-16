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
            _ = LogCapture.startVerboseCapture()
            AuthDiagnostics.shared.clear()
            AuthDiagnostics.shared.configureAmplifyVerboseLogging()
            try Amplify.add(plugin: AuthDiagnosticsLoggingPlugin())
            try Amplify.add(plugin: AWSCognitoAuthPlugin())
            try Amplify.add(plugin: AWSAPIPlugin())
            try Amplify.configure(with: .amplifyOutputs)
            AuthDiagnostics.shared.record("bootstrap", "Amplify configured successfully")
        } catch {
            AuthDiagnostics.shared.record("bootstrap", "Amplify configure failed: \(String(describing: error))")
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
