# Amplify Swift Issue Report Template

Repository used for repro:

- `amplify-swift-ios-repros`

Relevant files:

- `amplify/auth/resource.ts`
- `amplify/data/resource.ts`
- `amplify/functions/failHostedUISignUp/handler.ts`
- `ios/App/AmplifySwiftReproLabApp.swift`
- `ios/App/SubscriptionProbeStore.swift`
- `ios/App/ContentView.swift`

## Issue A: GraphQL subscription does not recover after background -> foreground

### Summary

After upgrading `amplify-swift`, our app more frequently reaches a state where GraphQL subscriptions do not return to `connected` after the app returns from background. In the production app this eventually surfaces a "please restart the app" message. The attached repro reduces the app to:

- Cognito auth
- AppSync GraphQL API
- one `onCreate` subscription
- background/foreground subscription stop/start
- watchdog banner when reconnection does not complete

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
8. Tap `Create Probe Item` and confirm the subscription log receives the item.
9. Send the app to background.
10. Bring the app back to foreground.
11. Observe the connection badge and event log.

### Expected behavior

After returning to foreground, the restarted subscription should consistently emit a `.connection(.connected)` event and continue receiving data.

### Actual behavior

Sometimes the subscription does not recover to `connected` after foreground. In the repro app, the watchdog eventually shows:

`Subscription did not recover after foreground. Please fully close and reopen the app.`

### Notes

- The repro uses custom GraphQL documents to keep the project minimal.
- The issue appears around subscription reconnection, not initial connection.
- The real app has multiple subscriptions, but this repro reduces it to a single subscription.

### Attachments to include

- App log output around background/foreground
- `amplify_outputs.json` used during repro
- Video capture if the connection badge remains stuck at `connecting` or `disconnected`

## Issue B: Hosted UI sign-up fails repeatedly and app becomes stuck

### Summary

We also want to isolate a Hosted UI problem where, after sign-up fails twice, the app can end up in a state where further auth actions appear blocked or no longer progress correctly.

This repro intentionally forces sign-up failure in a Cognito pre-sign-up trigger when the email starts with `fail-hostedui`.

### Amplify Swift version

- `2.58.1`

### Repro environment

- Xcode: `26.3`
- iOS: `<fill>`
- Device or simulator: `<fill>`
- Backend type: `Amplify Gen 2 sandbox`

### Backend behavior used for repro

The pre-sign-up trigger rejects emails matching this pattern:

- `fail-hostedui-<anything>@...`

Example:

- `fail-hostedui-1@example.com`

### Repro steps

1. Start the repro project backend and run the iOS app.
2. Tap `Open Hosted UI`.
3. In the managed login UI, choose sign up.
4. Use `fail-hostedui-1@example.com` and a valid password.
5. Confirm sign-up fails.
6. Repeat the same failed sign-up a second time.
7. Tap `Open Hosted UI` again.
8. Observe:
   - whether the web UI opens
   - whether auth Hub events still fire
   - whether the app remains stuck in an in-progress state
   - whether sign-out or later retries stop working

### Expected behavior

Even after repeated Hosted UI sign-up failures, the app should remain able to open Hosted UI again and continue normal auth retries.

### Actual behavior

After repeated sign-up failures, the app may become stuck or stop progressing correctly on later Hosted UI attempts.

### Notes

- This repro intentionally avoids the production app's custom auth recovery logic.
- The goal is to confirm whether the stuck state can happen with a near-minimal Amplify Swift + Cognito Hosted UI setup.
- The repro logs both Hub auth events and `fetchAuthSession()` transitions in-app.

### Attachments to include

- App log output covering all three Hosted UI attempts
- Video of the second and third attempts
- Whether the issue reproduces on simulator, physical device, or both

## Short issue title candidates

- `GraphQL subscription may fail to reconnect after iOS app returns from background`
- `signInWithWebUI may become stuck after repeated Hosted UI sign-up failures`

## Suggested source links to include

- Repro README: `amplify-swift-ios-repros/README.md`
- Web UI sign-in docs: `https://docs.amplify.aws/swift/frontend/auth/web-ui-sign-in/`
- External provider config docs: `https://docs.amplify.aws/swift/build-a-backend/auth/concepts/external-identity-providers/`
