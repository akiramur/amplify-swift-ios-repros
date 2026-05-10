import Amplify
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: SubscriptionProbeStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let banner = store.restartRequiredMessage {
                    Text(banner)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                HStack {
                    Label("Auth", systemImage: "person.crop.circle")
                    Spacer()
                    Text(store.isSignedIn ? "signed-in" : "signed-out")
                        .font(.caption.monospaced().weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background((store.isSignedIn ? Color.green : Color.gray).opacity(0.18))
                        .foregroundStyle(store.isSignedIn ? Color.green : Color.gray)
                        .clipShape(Capsule())
                }

                HStack {
                    Label("Connection", systemImage: "dot.radiowaves.left.and.right")
                    Spacer()
                    Text(store.connectionState.label)
                        .font(.caption.monospaced().weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(store.connectionState.color.opacity(0.18))
                        .foregroundStyle(store.connectionState.color)
                        .clipShape(Capsule())
                }

                HStack(spacing: 12) {
                    Button("Open Hosted UI") {
                        Task { await store.signInWithHostedUI() }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Sign Out") {
                        Task { await store.signOut() }
                    }
                    .buttonStyle(.bordered)

                    Button("Check Session") {
                        Task { await store.refreshSession() }
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 12) {
                    Button("Refresh") {
                        Task { await store.refreshItems() }
                    }
                    .buttonStyle(.bordered)

                    Button("Restart Subscriptions") {
                        Task { await store.restartSubscription(reason: "manual") }
                    }
                    .buttonStyle(.bordered)

                    Button("Create Probe Item") {
                        Task { await store.createProbeItem() }
                    }
                    .buttonStyle(.borderedProminent)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Subscription Workers")
                        .font(.headline)

                    ForEach(store.workerSnapshots) { worker in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(worker.label)
                                    .font(.subheadline.monospaced().weight(.semibold))
                                Spacer()
                                Text(worker.state.label)
                                    .font(.caption.monospaced().weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(worker.state.color.opacity(0.18))
                                    .foregroundStyle(worker.state.color)
                                    .clipShape(Capsule())
                            }

                            Text("attempt \(worker.attempt)  \(worker.lastEvent)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Latest Items")
                        .font(.headline)

                    if !store.isSignedIn {
                        ContentUnavailableView("Sign in required", systemImage: "lock")
                    } else if store.items.isEmpty {
                        ContentUnavailableView("No items", systemImage: "tray")
                    } else {
                        List(store.items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.content)
                                Text(item.updatedAt ?? item.createdAt ?? "")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .listStyle(.plain)
                        .frame(minHeight: 180)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Event Log")
                        .font(.headline)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(store.logs.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption.monospaced())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
            .navigationTitle("Subscription Repro")
            .task {
                await store.bootstrapIfNeeded()
            }
        }
    }
}

private extension SubscriptionConnectionState {
    var label: String {
        switch self {
        case .connected:
            return "connected"
        case .connecting:
            return "connecting"
        case .disconnected:
            return "disconnected"
        @unknown default:
            return "unknown"
        }
    }

    var color: Color {
        switch self {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .red
        @unknown default:
            return .gray
        }
    }
}
