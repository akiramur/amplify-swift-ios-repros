# Amplify Swift iOS Repros

This is a small monorepo for building and sharing Amplify Swift iOS repro cases.

The current seed scenario focuses on a GraphQL subscription reconnection issue after the app returns from background.

It intentionally removes Jukeme-specific code and keeps only:

- Amplify Gen 2 backend
- Email/password auth
- Hosted UI sign-in
- One GraphQL model
- One `onCreate` subscription
- Background/foreground restart logic
- A watchdog that surfaces a restart-required banner when the subscription does not return to `connected`

## Structure

```text
amplify-swift-ios-repros/
├── amplify/           # Amplify Gen 2 backend
├── ios/               # XcodeGen-based iOS app
├── package.json
└── README.md
```

## Backend

The backend defines a single model:

- `ReproItem`

Authorization uses Cognito User Pool auth only.

## iOS app behavior

After sign-in, the app:

1. Fetches `listReproItems`
2. Starts `onCreateReproItem`
3. Cancels the subscription when the app enters background
4. Starts it again when the app becomes active
5. Shows a red banner if the subscription does not report `connected` before the watchdog timeout

This is intentionally close to the failure mode you described in Jukeme.

For Hosted UI repro, the app also:

1. Launches `Amplify.Auth.signInWithWebUI`
2. Logs auth Hub events and `fetchAuthSession()` results
3. Lets you force sign-up failure with a pre-sign-up trigger
4. Keeps the log visible so you can see whether retry taps stop doing anything after repeated failures

## Setup

### 1. Install backend dependencies

```bash
cd amplify-swift-ios-repros
npm install
```

### 2. Start the sandbox

```bash
npx ampx sandbox
```

Wait until `amplify_outputs.json` is generated at the repo root.

### 3. Generate the Xcode project

```bash
cd ios
xcodegen generate
open AmplifySwiftReproLab.xcodeproj
```

### 4. Resolve Swift packages in Xcode

The project depends on:

- `amplify-swift` `2.58.1`

### 5. Run the app

Sign up with email/password, sign in, then use the app on a simulator or device.

## Repro flow

1. Launch the app and sign in.
2. Confirm the connection state becomes `connected`.
3. Tap `Create Probe Item` and confirm:
   - the mutation succeeds
   - the subscription log receives the created item
4. Put the app in background for a while.
5. Bring it back to foreground.
6. Watch the connection log and state badge.
7. If the watchdog expires before `connected`, the app shows the red restart banner.

## Hosted UI failure repro flow

The backend intentionally rejects sign-up emails whose address starts with `fail-hostedui`.

Use a test address like:

- `fail-hostedui-1@example.com`

Steps:

1. Launch the app.
2. Tap `Open Hosted UI`.
3. In Cognito managed login, choose sign up.
4. Use `fail-hostedui-1@example.com` and any password that satisfies Cognito policy.
5. Confirm the sign-up fails.
6. Repeat the same failure a second time.
7. Tap `Open Hosted UI` again and inspect whether:
   - the web UI opens normally
   - auth Hub events continue to fire
   - the app gets stuck in an in-progress or signed-out state
   - further sign-in or sign-out actions stop working

This flow is aimed at reproducing the "after two Hosted UI sign-up failures, the app cannot proceed" symptom without Jukeme-specific recovery logic.

## Files to attach when reporting the issue

- `ios/App/SubscriptionProbeStore.swift`
- `ios/App/ContentView.swift`
- `amplify/auth/resource.ts`
- `amplify/functions/failHostedUISignUp/handler.ts`
- `amplify/data/resource.ts`
- exact Amplify Swift version
- iOS version
- Xcode version
- device/simulator type
- console logs around background and foreground transitions

## Notes

- This project uses custom GraphQL documents rather than generated Swift models to keep the repro small.
- `amplify_outputs.json` is bundled from the repo root into the iOS app target.
- Add more repro scenarios by extending the backend and adding dedicated screens or stores under `ios/App/`.
