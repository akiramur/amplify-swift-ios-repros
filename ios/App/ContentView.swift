import Amplify
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: SubscriptionProbeStore

    var body: some View {
        NavigationStack {
            ScrollView {
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

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Log Export")
                            .font(.headline)

                        Text("Use this after repro when the debugger is detached. Refresh creates snapshots from the current verbose log file and in-app event log.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button("Refresh Exports") {
                                store.refreshExportArtifacts()
                            }
                            .buttonStyle(.bordered)

                            if let verboseURL = store.verboseLogExportURL {
                                ShareLink(item: verboseURL) {
                                    Text("Export Verbose Log")
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Text("Verbose log unavailable")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 12) {
                            if let unifiedURL = store.unifiedLogExportURL {
                                ShareLink(item: unifiedURL) {
                                    Text("Export Unified Log")
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Text("Unified log unavailable")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 12) {
                            if let reportURL = store.reproReportExportURL {
                                ShareLink(item: reportURL) {
                                    Text("Export Repro Report")
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Text("Repro report unavailable")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Stress Mode")
                                .font(.headline)
                            Spacer()
                            Text(store.selectedStressProfile == .aligned ? "aligned" : "experimental")
                                .font(.caption.monospaced().weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background((store.selectedStressProfile == .aligned ? Color.blue : Color.orange).opacity(0.18))
                                .foregroundStyle(store.selectedStressProfile == .aligned ? Color.blue : Color.orange)
                                .clipShape(Capsule())
                            if store.isStressRunInFlight {
                                Text("running")
                                    .font(.caption.monospaced().weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.orange.opacity(0.18))
                                    .foregroundStyle(.orange)
                                    .clipShape(Capsule())
                                }
                        }

                        HStack(spacing: 12) {
                            Button("Apply Aligned Profile") {
                                store.applyAlignedStressProfile()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Apply Experimental Profile") {
                                store.applyExperimentalStressProfile()
                            }
                            .buttonStyle(.bordered)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Aligned Controls")
                                .font(.subheadline.weight(.semibold))
                            Text("Keep this section close to ../jukebox-web-ts foreground/background behavior.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Stepper("Workers: \(store.stressConfig.workerCount)", value: Binding(
                                get: { store.stressConfig.workerCount },
                                set: { store.setWorkerCount($0) }
                            ), in: 1...12)

                            Stepper("Recovery bursts: \(store.stressConfig.recoveryBurstCount)", value: Binding(
                                get: { store.stressConfig.recoveryBurstCount },
                                set: { store.setRecoveryBurstCount($0) }
                            ), in: 1...10)

                            Stepper("Restart jitter: \(store.stressConfig.restartJitterMilliseconds) ms", value: Binding(
                                get: { store.stressConfig.restartJitterMilliseconds },
                                set: { store.setRestartJitterMilliseconds($0) }
                            ), in: 0...1000, step: 50)

                            Stepper("Query burst: \(store.stressConfig.queryBurstCount)", value: Binding(
                                get: { store.stressConfig.queryBurstCount },
                                set: { store.setQueryBurstCount($0) }
                            ), in: 1...6)
                        }
                        .padding(12)
                        .background(Color.blue.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Experimental Controls")
                                .font(.subheadline.weight(.semibold))
                            Text("These increase repro odds but can diverge from ../jukebox-web-ts and trigger unrelated failures.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Stepper("Mutation burst: \(store.stressConfig.mutationBurstCount)", value: Binding(
                                get: { store.stressConfig.mutationBurstCount },
                                set: { store.setMutationBurstCount($0) }
                            ), in: 0...6)

                            Stepper("Active recoveries: \(store.stressConfig.duplicateActiveRecoveryCount)", value: Binding(
                                get: { store.stressConfig.duplicateActiveRecoveryCount },
                                set: { store.setDuplicateActiveRecoveryCount($0) }
                            ), in: 1...5)

                            Stepper("Background stop delay: \(store.stressConfig.backgroundStopDelayMilliseconds) ms", value: Binding(
                                get: { store.stressConfig.backgroundStopDelayMilliseconds },
                                set: { store.setBackgroundStopDelayMilliseconds($0) }
                            ), in: 0...2000, step: 100)

                            Toggle("Stop on inactive", isOn: Binding(
                                get: { store.stressConfig.stopOnInactive },
                                set: { store.setStopOnInactive($0) }
                            ))

                            Toggle("Skip prestart stop", isOn: Binding(
                                get: { store.stressConfig.skipPrestartStop },
                                set: { store.setSkipPrestartStop($0) }
                            ))
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        HStack(spacing: 12) {
                            Button("Run Stress Burst") {
                                Task { await store.runStressRecoveryBurst() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.isStressRunInFlight || !store.isSignedIn)

                            Button("Restart With Settings") {
                                Task { await store.restartSubscription(reason: "stress-config") }
                            }
                            .buttonStyle(.bordered)
                            .disabled(store.isStressRunInFlight || !store.isSignedIn)
                        }
                    }
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

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
                        .frame(minHeight: 260)
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
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
