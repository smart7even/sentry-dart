import Cocoa
import FlutterMacOS
import Sentry

class MainFlutterWindow: NSWindow {
  private let _channel = "example.flutter.sentry.io"
  private var _transaction: Span?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // swiftlint:disable:next force_cast
    let controller = self.contentViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: _channel,
                                    binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler(handleMessage)

    super.awakeFromNib()
  }

    private func handleMessage(call: FlutterMethodCall, result: @escaping FlutterResult) {
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
