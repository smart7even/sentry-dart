import UIKit
import Flutter
import Sentry

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private let _channel = "example.flutter.sentry.io"
  private var _transaction: Span?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    guard let controller = window?.rootViewController as? FlutterViewController else {
      fatalError("rootViewController is not type FlutterViewController")
    }

    let channel = FlutterMethodChannel(name: _channel,
                            binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler(handleMessage)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleMessage(call: FlutterMethodCall, result: FlutterResult) {
    if call.method == "fatalError" {
      fatalError("fatalError")
    } else if call.method == "crash" {
      SentrySDK.crash()
    } else if call.method == "capture" {
      let exception = NSException(
        name: NSExceptionName("NSException"),
        reason: "Swift NSException Captured",
        userInfo: ["details": "lots"])
      SentrySDK.capture(exception: exception)
    } else if call.method == "capture_message" {
      if let transaction = self._transaction {
        transaction.finish()
        self._transaction = nil
      } else {
        self._transaction = SentrySDK.startTransaction(
          name: "flutter-swift-transaction",
          operation: "test"
        )
      }
    } else if call.method == "throw" {
      Buggy.throw()
    }
    result("")
  }
}
