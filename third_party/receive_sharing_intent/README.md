# receive_sharing_intent (local fork)

Upstream: [receive_sharing_intent 1.8.1](https://pub.dev/packages/receive_sharing_intent)

This fork adds Swift Package Manager support for iOS so the app can use Flutter's
SPM integration without CocoaPods fallback for this plugin.

Changes vs upstream:

- Added `ios/receive_sharing_intent/Package.swift`
- Moved native sources to `ios/receive_sharing_intent/Sources/receive_sharing_intent/`
- Replaced ObjC registrar with pure-Swift `@objc(ReceiveSharingIntentPlugin)` shim (SPM does not allow mixed ObjC/Swift targets)
- Added `FlutterSceneLifeCycleDelegate` for UIScene URL / user-activity handling (keeps AppDelegate hooks for legacy apps)
- Updated `receive_sharing_intent.podspec` source paths (CocoaPods fallback)

Dart API is unchanged.
