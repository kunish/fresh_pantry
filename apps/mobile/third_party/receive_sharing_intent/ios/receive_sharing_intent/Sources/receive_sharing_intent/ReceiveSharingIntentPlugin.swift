import Flutter

/// ObjC-visible registrar shim so GeneratedPluginRegistrant keeps working under SPM.
@objc(ReceiveSharingIntentPlugin)
public class ReceiveSharingIntentPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    SwiftReceiveSharingIntentPlugin.register(with: registrar)
  }
}
