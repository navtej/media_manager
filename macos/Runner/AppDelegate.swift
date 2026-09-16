import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var terminationRequestInFlight = false
  private var terminationApproved = false

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if terminationApproved {
      return .terminateNow
    }

    if terminationRequestInFlight {
      return .terminateLater
    }

    guard let flutterViewController = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return .terminateNow
    }

    terminationRequestInFlight = true
    let channel = FlutterMethodChannel(
      name: "com.example.moviemanager/app_lifecycle",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.invokeMethod("prepareForTermination", arguments: nil) { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }

        if let error = result as? FlutterError {
          print("DEBUG SWIFT: Termination cleanup failed: \(error.message ?? error.code)")
          self.terminationRequestInFlight = false
          sender.reply(toApplicationShouldTerminate: false)
          return
        }

        self.terminationApproved = true
        sender.reply(toApplicationShouldTerminate: true)
      }
    }

    return .terminateLater
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
