import Cocoa
import FlutterMacOS
import Foundation
import FoundationModels

@available(macOS 15.0, *)
actor AILanguageModelManager {
    static let shared = AILanguageModelManager()
    
    // Cache the model instance so we don't load it repeatedly, only the session needs to be fresh
    private var model: SystemLanguageModel?
    private var isInitializing = false
    
    private init() {}
    
    enum AIError: LocalizedError {
        case modelNotAvailable
        case whisperRuntimeMissing
        case transcriptionFailed(String)

        var errorDescription: String? {
            switch self {
            case .modelNotAvailable:
                return "Apple Foundation model is not available."
            case .whisperRuntimeMissing:
                return "Bundled whisper runtime is missing from the app bundle."
            case .transcriptionFailed(let message):
                let cleanedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
                return cleanedMessage.isEmpty
                    ? "whisper-cli failed without diagnostic output."
                    : cleanedMessage
            }
        }
    }
    
    private func ensureModelLoaded() async throws {
        if model != nil { return }
        if isInitializing {
             while isInitializing {
                try await Task.sleep(nanoseconds: 100_000_000)
                if model != nil { return }
             }
        }
        
        isInitializing = true
        defer { isInitializing = false }
        
        let newModel = SystemLanguageModel(useCase: .contentTagging)
        let availability = newModel.availability
        print("DEBUG SWIFT: Model availability: \(availability)")
        
        guard case .available = availability else {
            throw AIError.modelNotAvailable
        }
        self.model = newModel
    }

    func extractTags(from text: String) async throws -> [String] {
        try await ensureModelLoaded()
        
        guard let model = self.model else {
            throw AIError.modelNotAvailable
        }
        
        let instructions = "Provide two to five tags based on this text. Format as a comma separated list of single words. If the text conatins tags starting with #, prioritize those relevant tags."
        
        // Create FRESH session for each task
        let session = LanguageModelSession(model: model, instructions: instructions)
        print("DEBUG SWIFT: Fresh session created.")
        
        let truncatedText = String(text.prefix(3800))
        let response = try await session.respond(to: truncatedText)
        
        let responseText = response.content
        print("DEBUG SWIFT: Raw Content: [\(responseText)]")
        
        let tags = responseText
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count >= 2 }
        
        return Array(Set(tags))
    }

    nonisolated static func transcribeAudio(audioPath: String, modelPath: String) throws -> String {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: audioPath) else {
            throw AIError.transcriptionFailed("Audio file is missing.")
        }
        guard fileManager.fileExists(atPath: modelPath) else {
            throw AIError.transcriptionFailed("Model file is missing.")
        }

        guard let cliPath = resolveWhisperCLIPath() else {
            throw AIError.whisperRuntimeMissing
        }

        let outputBase = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("summary_\(UUID().uuidString)")
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = [
            "-m", modelPath,
            "-f", audioPath,
            "-of", outputBase,
            "-otxt",
        ]
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let outputText = String(data: outputData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let diagnostic = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AIError.transcriptionFailed(
                diagnostic.isEmpty
                    ? "whisper-cli exited with status \(process.terminationStatus)."
                    : diagnostic
            )
        }

        let transcriptURL = URL(fileURLWithPath: "\(outputBase).txt")
        guard let transcript = try? String(contentsOf: transcriptURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !transcript.isEmpty else {
            throw AIError.transcriptionFailed("Whisper produced an empty transcript.")
        }

        try? fileManager.removeItem(at: transcriptURL)
        return transcript
    }
}

private func resolveWhisperCLIPath() -> String? {
    let fileManager = FileManager.default
    if let bundledRuntime = Bundle.main.resourceURL?
        .appendingPathComponent("WhisperRuntime")
        .appendingPathComponent("whisper-cli")
        .path,
        fileManager.isExecutableFile(atPath: bundledRuntime) {
        return bundledRuntime
    }

    let explicitCandidates = [
        "/opt/homebrew/bin/whisper-cli",
        "/usr/local/bin/whisper-cli",
    ]

    for candidate in explicitCandidates where fileManager.isExecutableFile(atPath: candidate) {
        return candidate
    }

    let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
    for directory in pathValue.split(separator: ":") {
        let candidate = "\(directory)/whisper-cli"
        if fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }

    return nil
}

private var activeFolderAccess: [String: URL] = [:]

private func createFolderBookmark(path: String) throws -> String {
    let url = URL(fileURLWithPath: path)
    let didStartAccessing = url.startAccessingSecurityScopedResource()
    defer {
        if didStartAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }

    let data = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
    )
    return data.base64EncodedString()
}

private func startAccessingFolder(path: String, bookmark: String) throws -> Bool {
    if activeFolderAccess[path] != nil {
        return true
    }

    guard let data = Data(base64Encoded: bookmark) else {
        return false
    }

    var isStale = false
    let url = try URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
    )

    if isStale {
        return false
    }

    guard url.startAccessingSecurityScopedResource() else {
        return false
    }

    guard FileManager.default.fileExists(atPath: url.path) else {
        url.stopAccessingSecurityScopedResource()
        return false
    }

    activeFolderAccess[path] = url
    return true
}

private func stopAccessingFolder(path: String) {
    guard let url = activeFolderAccess.removeValue(forKey: path) else {
        return
    }
    url.stopAccessingSecurityScopedResource()
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    super.awakeFromNib()
    print("DEBUG SWIFT: awakeFromNib started")

    // Force window onto current space and disable state restoration
    self.isRestorable = false
    self.collectionBehavior = [.managed, .participatesInCycle]
    self.level = .normal
    
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.center()

    // Ensure window is visible and active
    self.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    
    print("DEBUG SWIFT: Window level: \(self.level), transparency: \(self.isOpaque), isVisible: \(self.isVisible)")

    let channel = FlutterMethodChannel(
      name: "com.example.moviemanager/natural_language",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    
    channel.setMethodCallHandler { (call, result) in
      if call.method == "analyzeText" {
        guard let args = call.arguments as? [String: Any],
              let text = args["text"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Text argument missing", details: nil))
          return
        }
        
        Task.detached(priority: .userInitiated) {
            if #available(macOS 15.0, *) {
                do {
                    let tags = try await AILanguageModelManager.shared.extractTags(from: text)
                    DispatchQueue.main.async {
                        result(tags)
                    }
                } catch {
                    print("DEBUG SWIFT: extractTags error: \(error)")
                    DispatchQueue.main.async {
                        result(FlutterError(code: "AI_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
	          } else {
	            DispatchQueue.main.async {
	              result(FlutterError(code: "UNSUPPORTED", message: "MacOS 15+ required", details: nil))
	            }
	          }
	        }
      } else if call.method == "transcribeAudio" {
        guard let args = call.arguments as? [String: Any],
              let audioPath = args["audioPath"] as? String,
              let modelPath = args["modelPath"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Audio or model path missing", details: nil))
          return
        }

        Task.detached(priority: .userInitiated) {
          do {
            let transcript = try AILanguageModelManager.transcribeAudio(
              audioPath: audioPath,
              modelPath: modelPath
            )
            DispatchQueue.main.async {
              result(transcript)
            }
          } catch {
            DispatchQueue.main.async {
              result(FlutterError(code: "TRANSCRIPTION_ERROR", message: error.localizedDescription, details: nil))
            }
          }
        }
      } else if call.method == "openInFinder" {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Path argument missing", details: nil))
          return
        }
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        result(nil)
      } else if call.method == "openFolder" {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Path argument missing", details: nil))
          return
        }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
        result(nil)
      } else if call.method == "createFolderBookmark" {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Path argument missing", details: nil))
          return
        }
        do {
          result(try createFolderBookmark(path: path))
        } catch {
          result(FlutterError(code: "BOOKMARK_ERROR", message: error.localizedDescription, details: nil))
        }
      } else if call.method == "startAccessingFolder" {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String,
              let bookmark = args["bookmark"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Path or bookmark argument missing", details: nil))
          return
        }
        do {
          result(try startAccessingFolder(path: path, bookmark: bookmark))
        } catch {
          result(FlutterError(code: "BOOKMARK_ERROR", message: error.localizedDescription, details: nil))
        }
      } else if call.method == "stopAccessingFolder" {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Path argument missing", details: nil))
          return
        }
        stopAccessingFolder(path: path)
        result(nil)
      } else if call.method == "playVideo" {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Path argument missing", details: nil))
          return
        }

        let folderPath = args["folderPath"] as? String
        let folderBookmark = args["folderBookmark"] as? String
        var didStartPlaybackAccess = false

        if let folderPath,
           let folderBookmark,
           !folderPath.isEmpty,
           !folderBookmark.isEmpty,
           activeFolderAccess[folderPath] == nil {
          do {
            didStartPlaybackAccess = try startAccessingFolder(path: folderPath, bookmark: folderBookmark)
            if !didStartPlaybackAccess {
              result(FlutterError(code: "BOOKMARK_ERROR", message: "Folder access needs repair. Reselect this folder in Settings.", details: nil))
              return
            }
          } catch {
            result(FlutterError(code: "BOOKMARK_ERROR", message: error.localizedDescription, details: nil))
            return
          }
        }

        let url = URL(fileURLWithPath: path)
        let opened = NSWorkspace.shared.open(url)
        if didStartPlaybackAccess, let folderPath {
          DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            stopAccessingFolder(path: folderPath)
          }
        }
        guard opened else {
          result(FlutterError(code: "PLAYBACK_ERROR", message: "Unable to open video.", details: nil))
          return
        }
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
  }
}
