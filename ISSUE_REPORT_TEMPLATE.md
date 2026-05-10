# Amplify Swift Issue Report Template

Repository used for repro:

- `amplify-swift-ios-repros`

Relevant files:

- `amplify/auth/resource.ts`
- `amplify/data/resource.ts`
- `ios/App/AmplifySwiftReproLabApp.swift`
- `ios/App/SubscriptionProbeStore.swift`
- `ios/App/ContentView.swift`

## Issue A: GraphQL subscription does not recover after background -> foreground

### Summary

After upgrading `amplify-swift`, our app more frequently reaches a state where GraphQL subscriptions do not return to `connected` after the app returns from background. In the production app this eventually surfaces a "please restart the app" message. The attached repro reduces the app to:

- Cognito auth
- AppSync GraphQL API
- three concurrent `onCreate` subscription workers
- background/foreground restart across all workers
- watchdog banner when one or more workers do not reconnect

### Amplify Swift version

- `2.58.1`

### Repro environment

- Xcode: `26.3`
- iOS: `<fill>`
- Device or simulator: `<fill>`
- Backend type: `Amplify Gen 2 sandbox`

### Repro steps

1. `cd amplify-swift-ios-repros`
2. `npm install`
3. `npx ampx sandbox`
4. `cd ios && xcodegen generate`
5. Open `AmplifySwiftReproLab.xcodeproj`
6. Run the app and sign in.
7. Confirm the connection badge becomes `connected`.
8. Tap `Create Probe Item` and confirm multiple subscription worker logs receive the item.
9. Send the app to background.
10. Bring the app back to foreground.
11. Observe the aggregate connection badge, each worker card, and the event log.

### Expected behavior

After returning to foreground, all restarted subscription workers should consistently emit `.connection(.connected)` and continue receiving data.

### Actual behavior

Sometimes one or more subscription workers do not recover to `connected` after foreground. In the repro app, the watchdog eventually shows:

`Subscription did not recover after foreground. Please fully close and reopen the app.`

### Notes

- The repro uses custom GraphQL documents to keep the project minimal.
- The issue appears around subscription reconnection, not initial connection.
- The real app has multiple subscriptions, but this repro reduces it to a single subscription.

### Attachments to include

- App log output around background/foreground
- `amplify_outputs.json` used during repro
- Video capture if the connection badge remains stuck at `connecting` or `disconnected`

## Short issue title candidates

- `GraphQL subscription may fail to reconnect after iOS app returns from background`

## Suggested source links to include

- Repro README: `amplify-swift-ios-repros/README.md`
- Web UI sign-in docs: `https://docs.amplify.aws/swift/frontend/auth/web-ui-sign-in/`
- External provider config docs: `https://docs.amplify.aws/swift/build-a-backend/auth/concepts/external-identity-providers/`
