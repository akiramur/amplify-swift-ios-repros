import Amplify
import AWSCognitoAuthPlugin
import Foundation
import SwiftUI
import UIKit

@MainActor
final class SubscriptionProbeStore: ObservableObject {
    struct ReproItem: Decodable, Identifiable {
        let id: String
        let content: String
        let createdAt: String?
        let updatedAt: String?
        let createdByDevice: String?
        let __typename: String?
    }

    private struct ListReproItemsResponse: Decodable {
        let items: [ReproItem]
    }

    private struct CreateReproItemResponse: Decodable {
        let id: String
        let content: String
        let createdAt: String?
        let updatedAt: String?
        let createdByDevice: String?
        let __typename: String?
    }

    @Published private(set) var items: [ReproItem] = []
    @Published private(set) var logs: [String] = []
    @Published private(set) var isSignedIn = false
    @Published private(set) var connectionState: SubscriptionConnectionState = .disconnected
    @Published var restartRequiredMessage: String?
    @Published private(set) var isHostedUIInProgress = false

    private var hasBootstrapped = false
    private var subscription: AmplifyAsyncThrowingSequence<GraphQLSubscriptionEvent<ReproItem>>?
    private var subscriptionTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var authHubToken: UnsubscribeToken?

    private let deviceLabel = UIDevice.current.name

    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        appendLog("bootstrap")
        startObservingAuthHub()
        await refreshSession()
        if isSignedIn {
            await refreshItems()
            await startSubscription(reason: "bootstrap")
        }
    }

    func handleScenePhase(_ phase: ScenePhase) async {
        switch phase {
        case .active:
            appendLog("scenePhase=active")
            await refreshSession()
            if isSignedIn {
                await refreshItems()
                await startSubscription(reason: "scene-active")
            }
        case .background:
            appendLog("scenePhase=background")
            stopSubscription(reason: "scene-background")
        case .inactive:
            appendLog("scenePhase=inactive")
        @unknown default:
            appendLog("scenePhase=unknown")
        }
    }

    func restartSubscription(reason: String) async {
        guard isSignedIn else {
            appendLog("restart skipped signed-out")
            return
        }
        stopSubscription(reason: "restart-\(reason)")
        await startSubscription(reason: reason)
    }

    func refreshSession() async {
        do {
            let session = try await Amplify.Auth.fetchAuthSession()
            isSignedIn = session.isSignedIn
            appendLog("auth session isSignedIn=\(session.isSignedIn)")
            if !session.isSignedIn {
                stopSubscription(reason: "session-signed-out")
                items = []
            }
        } catch {
            appendLog("auth session error \(error.localizedDescription)")
        }
    }

    func signInWithHostedUI() async {
        guard !isHostedUIInProgress else {
            appendLog("hostedUI ignored already in progress")
            return
        }

        isHostedUIInProgress = true
        appendLog("hostedUI start")
        defer {
            isHostedUIInProgress = false
        }

        do {
            let result = try await Amplify.Auth.signInWithWebUI(presentationAnchor: presentationAnchor)
            appendLog("hostedUI result isSignedIn=\(result.isSignedIn)")
            await refreshSession()
            if result.isSignedIn {
                await refreshItems()
                await startSubscription(reason: "hostedUI-success")
            }
        } catch {
            appendLog("hostedUI error \(String(describing: error))")
        }
    }

    func signOut() async {
        let result = await Amplify.Auth.signOut()
        appendLog("signOut result \(String(describing: result))")
        await refreshSession()
    }

    func refreshItems() async {
        guard isSignedIn else {
            appendLog("query skipped signed-out")
            return
        }

        let document = """
        query ListReproItems {
          listReproItems(limit: 50) {
            items {
              id
              content
              createdAt
              updatedAt
              createdByDevice
              __typename
            }
          }
        }
        """

        do {
            let request = GraphQLRequest<ListReproItemsResponse>(
                document: document,
                responseType: ListReproItemsResponse.self,
                decodePath: "listReproItems"
            )
            let response = try await Amplify.API.query(request: request)

            switch response {
            case .success(let payload):
                items = payload.items.sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
                appendLog("query success items=\(payload.items.count)")
            case .failure(let error):
                appendLog("query failure \(error.localizedDescription)")
            }
        } catch {
            appendLog("query throw \(error.localizedDescription)")
        }
    }

    func createProbeItem() async {
        guard isSignedIn else {
            appendLog("mutation skipped signed-out")
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let content = "probe \(timestamp)"
        let document = """
        mutation CreateReproItem($input: CreateReproItemInput!) {
          createReproItem(input: $input) {
            id
            content
            createdAt
            updatedAt
            createdByDevice
            __typename
          }
        }
        """

        let variables: [String: Any] = [
            "input": [
                "content": content,
                "createdByDevice": deviceLabel,
            ]
        ]

        do {
            let request = GraphQLRequest<CreateReproItemResponse>(
                document: document,
                variables: variables,
                responseType: CreateReproItemResponse.self,
                decodePath: "createReproItem"
            )
            let response = try await Amplify.API.mutate(request: request)

            switch response {
            case .success(let created):
                appendLog("mutation success id=\(created.id)")
                if !items.contains(where: { $0.id == created.id }) {
                    items.insert(
                        ReproItem(
                            id: created.id,
                            content: created.content,
                            createdAt: created.createdAt,
                            updatedAt: created.updatedAt,
                            createdByDevice: created.createdByDevice,
                            __typename: created.__typename
                        ),
                        at: 0
                    )
                }
            case .failure(let error):
                appendLog("mutation failure \(error.localizedDescription)")
            }
        } catch {
            appendLog("mutation throw \(error.localizedDescription)")
        }
    }

    private func startSubscription(reason: String) async {
        guard isSignedIn else {
            appendLog("subscription start skipped signed-out")
            return
        }

        stopSubscription(reason: "prestart-\(reason)")
        restartRequiredMessage = nil

        let document = """
        subscription OnCreateReproItem {
          onCreateReproItem {
            id
            content
            createdAt
            updatedAt
            createdByDevice
            __typename
          }
        }
        """

        appendLog("subscription start reason=\(reason)")
        let request = GraphQLRequest<ReproItem>(
            document: document,
            responseType: ReproItem.self,
            decodePath: "onCreateReproItem"
        )

        let sequence = Amplify.API.subscribe(request: request)
        subscription = sequence
        connectionState = .connecting
        startWatchdog(context: reason)

        subscriptionTask = Task { [weak self] in
            guard let self else { return }

            do {
                for try await event in sequence {
                    switch event {
                    case .connection(let state):
                        self.connectionState = state
                        self.appendLog("subscription connection \(state)")
                        if state == .connected {
                            self.watchdogTask?.cancel()
                            self.watchdogTask = nil
                        }
                    case .data(let result):
                        switch result {
                        case .success(let item):
                            self.appendLog("subscription data id=\(item.id)")
                            self.items.removeAll { $0.id == item.id }
                            self.items.insert(item, at: 0)
                        case .failure(let error):
                            self.appendLog("subscription data failure \(error.localizedDescription)")
                        }
                    }
                }
                self.appendLog("subscription loop ended")
                self.connectionState = .disconnected
            } catch {
                self.appendLog("subscription throw \(error.localizedDescription)")
                self.connectionState = .disconnected
            }
        }
    }

    private func stopSubscription(reason: String) {
        appendLog("subscription stop reason=\(reason)")
        watchdogTask?.cancel()
        watchdogTask = nil
        subscription?.cancel()
        subscription = nil
        subscriptionTask?.cancel()
        subscriptionTask = nil
        connectionState = .disconnected
    }

    private func startWatchdog(context: String) {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            guard self.connectionState != .connected else { return }
            self.restartRequiredMessage = "Subscription did not recover after foreground. Please fully close and reopen the app."
            self.appendLog("watchdog timeout context=\(context)")
        }
    }

    private func appendLog(_ message: String) {
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date()))  \(message)"
        logs.insert(line, at: 0)
        if logs.count > 200 {
            logs.removeLast(logs.count - 200)
        }
    }

    private var presentationAnchor: UIWindow {
        guard
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
        else {
            return UIWindow(frame: .zero)
        }
        return window
    }

    private func startObservingAuthHub() {
        authHubToken = Amplify.Hub.listen(to: .auth) { [weak self] payload in
            Task { @MainActor in
                self?.appendLog("hub auth \(payload.eventName)")
                switch payload.eventName {
                case HubPayload.EventName.Auth.signedIn:
                    self?.isSignedIn = true
                case HubPayload.EventName.Auth.signedOut, HubPayload.EventName.Auth.sessionExpired:
                    self?.isSignedIn = false
                    self?.stopSubscription(reason: "hub-auth-state")
                    self?.items = []
                default:
                    break
                }
            }
        }
    }
}
