import Cocoa
import FlutterMacOS
import SwiftUI

private struct NativeWindowCommandsScene: Scene {
  var body: some Scene {
    WindowGroup {
      EmptyView()
    }
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)
    .commands {
      CommandGroup(replacing: .newItem) {}
    }
  }
}

@main
class AppDelegate: FlutterAppDelegate {
  private var terminationRequestInFlight = false
  private var terminationApproved = false
  @MainActor private lazy var nativeWindowCommands = NSHostingSceneRepresentation {
    NativeWindowCommandsScene()
  }

  override func applicationWillFinishLaunching(_ notification: Notification) {
    super.applicationWillFinishLaunching(notification)
    NSApp.addSceneRepresentation(nativeWindowCommands)
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    DispatchQueue.main.async { [weak self] in
      self?.ensureWindowMenuCommands()
    }
  }

  private func ensureWindowMenuCommands() {
    guard let menu = NSApp.windowsMenu else { return }
    let hasStandardCommands = menu.items.contains { $0.title == "Minimize" }
      && menu.items.contains { $0.title == "Zoom" }
    guard !hasStandardCommands else { return }

    let commands = [
      NSMenuItem(
        title: "Minimize",
        action: #selector(NSWindow.performMiniaturize(_:)),
        keyEquivalent: "m"
      ),
      NSMenuItem(
        title: "Bring All to Front",
        action: #selector(NSApplication.arrangeInFront(_:)),
        keyEquivalent: ""
      ),
      NSMenuItem(
        title: "Zoom",
        action: #selector(NSWindow.performZoom(_:)),
        keyEquivalent: ""
      ),
      NSMenuItem(
        title: "Fill",
        action: #selector(MainFlutterWindow.fillWindow(_:)),
        keyEquivalent: ""
      ),
      NSMenuItem(
        title: "Center",
        action: #selector(MainFlutterWindow.centerWindow(_:)),
        keyEquivalent: ""
      ),
      NSMenuItem.separator(),
      NSMenuItem(
        title: "Enter Full Screen",
        action: #selector(NSWindow.toggleFullScreen(_:)),
        keyEquivalent: ""
      ),
    ]
    for command in commands.reversed() {
      menu.insertItem(command, at: 0)
    }
  }

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
