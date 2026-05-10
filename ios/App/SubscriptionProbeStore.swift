import Amplify
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

    struct WorkerSnapshot: Identifiable {
        let id: String
        let label: String
        let attempt: Int
        let state: SubscriptionConnectionState
        let lastEvent: String
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

    private struct WorkerRuntime {
        let id: String
        let label: String
        var attempt = 0
        var state: SubscriptionConnectionState = .disconnected
        var lastEvent = "idle"
        var subscription: AmplifyAsyncThrowingSequence<GraphQLSubscriptionEvent<ReproItem>>?
        var task: Task<Void, Never>?
        var watchdog: Task<Void, Never>?
    }

    @Published private(set) var items: [ReproItem] = []
    @Published private(set) var logs: [String] = []
    @Published private(set) var workerSnapshots: [WorkerSnapshot] = []
    @Published private(set) var isSignedIn = false
    @Published private(set) var connectionState: SubscriptionConnectionState = .disconnected
    @Published var restartRequiredMessage: String?
    @Published private(set) var isHostedUIInProgress = false

    private static let workerDefinitions = [
        ("subscription-a", "service-a"),
        ("subscription-b", "service-b"),
        ("subscription-c", "service-c"),
    ]

    private let deviceLabel = UIDevice.current.name
    private let subscriptionDocument = """
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

    private var hasBootstrapped = false
    private var authHubToken: UnsubscribeToken?
    private var currentScenePhaseLabel = "uninitialized"
    private var workers: [String: WorkerRuntime]

    init() {
        workers = Dictionary(
            uniqueKeysWithValues: Self.workerDefinitions.map { id, label in
                (id, WorkerRuntime(id: id, label: label))
            }
        )
        refreshWorkerSnapshots()
    }

    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        appendLog("bootstrap")
        startObservingAuthHub()
        await refreshSession()
        if isSignedIn {
            await runForegroundRecovery(reason: "bootstrap")
        }
    }

    func handleScenePhase(_ phase: ScenePhase) async {
        currentScenePhaseLabel = phase.logLabel
        switch phase {
        case .active:
            appendLog("scenePhase=active")
            await refreshSession()
            if isSignedIn {
                await runForegroundRecovery(reason: "scene-active")
            }
        case .background:
            appendLog("scenePhase=background")
            stopAllSubscriptions(reason: "scene-background")
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
        stopAllSubscriptions(reason: "restart-\(reason)")
        startAllSubscriptions(reason: reason)
    }

    func refreshSession() async {
        do {
            let session = try await Amplify.Auth.fetchAuthSession()
            isSignedIn = session.isSignedIn
            appendLog("auth session isSignedIn=\(session.isSignedIn)")
            if !session.isSignedIn {
                stopAllSubscriptions(reason: "session-signed-out")
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
                await runForegroundRecovery(reason: "hostedUI-success")
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

    private func runForegroundRecovery(reason: String) async {
        appendLog("foreground recovery reason=\(reason) workers=\(workers.count)")
        let refreshTask = Task { [weak self] in
            await self?.refreshItems()
        }
        let restartTask = Task { [weak self] in
            self?.startAllSubscriptions(reason: reason)
        }
        _ = await refreshTask.value
        _ = await restartTask.value
    }

    private func startAllSubscriptions(reason: String) {
        guard isSignedIn else {
            appendLog("subscription start skipped signed-out")
            return
        }

        restartRequiredMessage = nil
        appendLog("subscriptions start reason=\(reason) scene=\(currentScenePhaseLabel)")
        for workerID in Self.workerDefinitions.map(\.0) {
            stopWorkerSubscription(id: workerID, reason: "prestart-\(reason)")
        }
        for workerID in Self.workerDefinitions.map(\.0) {
            startWorkerSubscription(id: workerID, reason: reason)
        }
    }

    private func startWorkerSubscription(id: String, reason: String) {
        guard isSignedIn, var worker = workers[id] else { return }

        worker.attempt += 1
        let attempt = worker.attempt
        worker.state = .connecting
        worker.lastEvent = "starting:\(reason)"
        workers[id] = worker
        refreshWorkerSnapshots()
        appendWorkerLog(id: id, "start attempt=\(attempt) reason=\(reason) scene=\(currentScenePhaseLabel)")

        let request = GraphQLRequest<ReproItem>(
            document: subscriptionDocument,
            responseType: ReproItem.self,
            decodePath: "onCreateReproItem"
        )
        let sequence = Amplify.API.subscribe(request: request)

        worker.subscription = sequence
        worker.watchdog = startWorkerWatchdog(
            id: id,
            attempt: attempt,
            context: "attempt=\(attempt) reason=\(reason) scene=\(currentScenePhaseLabel)"
        )

        let task = Task { [weak self] in
            guard let self else { return }

            do {
                for try await event in sequence {
                    switch event {
                    case .connection(let state):
                        await self.handleWorkerConnection(id: id, attempt: attempt, state: state)
                    case .data(let result):
                        switch result {
                        case .success(let item):
                            await self.handleWorkerDataSuccess(id: id, attempt: attempt, item: item)
                        case .failure(let error):
                            await self.handleWorkerDataFailure(
                                id: id,
                                attempt: attempt,
                                message: error.localizedDescription
                            )
                        }
                    }
                }
                await self.finishWorkerLoop(id: id, attempt: attempt, result: "loop-ended")
            } catch is CancellationError {
                await self.finishWorkerLoop(id: id, attempt: attempt, result: "cancelled")
            } catch {
                await self.finishWorkerLoop(
                    id: id,
                    attempt: attempt,
                    result: "throw:\(error.localizedDescription)"
                )
            }
        }

        worker.task = task
        workers[id] = worker
        recalculateAggregateState()
        refreshWorkerSnapshots()
    }

    private func stopAllSubscriptions(reason: String) {
        appendLog("subscriptions stop reason=\(reason) scene=\(currentScenePhaseLabel)")
        for workerID in Self.workerDefinitions.map(\.0) {
            stopWorkerSubscription(id: workerID, reason: reason)
        }
    }

    private func stopWorkerSubscription(id: String, reason: String) {
        guard var worker = workers[id] else { return }

        appendWorkerLog(id: id, "stop attempt=\(worker.attempt) reason=\(reason) scene=\(currentScenePhaseLabel)")
        worker.watchdog?.cancel()
        worker.watchdog = nil
        worker.subscription?.cancel()
        worker.subscription = nil
        worker.task?.cancel()
        worker.task = nil
        worker.state = .disconnected
        worker.lastEvent = "stopped:\(reason)"
        workers[id] = worker
        recalculateAggregateState()
        refreshWorkerSnapshots()
    }

    private func handleWorkerConnection(
        id: String,
        attempt: Int,
        state: SubscriptionConnectionState
    ) {
        guard var worker = workers[id], worker.attempt == attempt else { return }

        worker.state = state
        worker.lastEvent = "connection:\(state)"
        if state == .connected {
            worker.watchdog?.cancel()
            worker.watchdog = nil
        }
        workers[id] = worker
        appendWorkerLog(id: id, "connection attempt=\(attempt) state=\(state)")
        recalculateAggregateState()
        refreshWorkerSnapshots()
    }

    private func handleWorkerDataSuccess(id: String, attempt: Int, item: ReproItem) {
        guard var worker = workers[id], worker.attempt == attempt else { return }

        worker.lastEvent = "data:\(item.id)"
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        workers[id] = worker
        appendWorkerLog(id: id, "data attempt=\(attempt) id=\(item.id)")
        refreshWorkerSnapshots()
    }

    private func handleWorkerDataFailure(id: String, attempt: Int, message: String) {
        guard var worker = workers[id], worker.attempt == attempt else { return }

        worker.lastEvent = "data-failure"
        workers[id] = worker
        appendWorkerLog(id: id, "data failure attempt=\(attempt) \(message)")
        refreshWorkerSnapshots()
    }

    private func finishWorkerLoop(id: String, attempt: Int, result: String) {
        guard var worker = workers[id], worker.attempt == attempt else { return }

        worker.subscription = nil
        worker.task = nil
        worker.watchdog?.cancel()
        worker.watchdog = nil
        worker.state = .disconnected
        worker.lastEvent = result
        workers[id] = worker
        appendWorkerLog(id: id, "finish attempt=\(attempt) result=\(result)")
        recalculateAggregateState()
        refreshWorkerSnapshots()
    }

    private func startWorkerWatchdog(id: String, attempt: Int, context: String) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self else { return }
            await self.handleWorkerWatchdogTimeout(id: id, attempt: attempt, context: context)
        }
    }

    private func handleWorkerWatchdogTimeout(id: String, attempt: Int, context: String) {
        guard let worker = workers[id], worker.attempt == attempt else { return }
        guard worker.state != .connected else { return }

        restartRequiredMessage = "One or more subscriptions did not recover after foreground. Please fully close and reopen the app."
        appendWorkerLog(id: id, "watchdog timeout context=\(context)")
    }

    private func recalculateAggregateState() {
        let states = workers.values.map(\.state)
        if !states.isEmpty && states.allSatisfy({ $0 == .connected }) {
            connectionState = .connected
        } else if states.contains(.connecting) || states.contains(.connected) {
            connectionState = .connecting
        } else {
            connectionState = .disconnected
        }
    }

    private func refreshWorkerSnapshots() {
        workerSnapshots = Self.workerDefinitions.compactMap { id, _ in
            guard let worker = workers[id] else { return nil }
            return WorkerSnapshot(
                id: worker.id,
                label: worker.label,
                attempt: worker.attempt,
                state: worker.state,
                lastEvent: worker.lastEvent
            )
        }
    }

    private func appendWorkerLog(id: String, _ message: String) {
        let label = workers[id]?.label ?? id
        appendLog("[\(label)] \(message)")
    }

    private func appendLog(_ message: String) {
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date()))  \(message)"
        logs.insert(line, at: 0)
        if logs.count > 300 {
            logs.removeLast(logs.count - 300)
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
                    self?.stopAllSubscriptions(reason: "hub-auth-state")
                    self?.items = []
                default:
                    break
                }
            }
        }
    }
}

private extension ScenePhase {
    var logLabel: String {
        switch self {
        case .active:
            return "active"
        case .inactive:
            return "inactive"
        case .background:
            return "background"
        @unknown default:
            return "unknown"
        }
    }
}
