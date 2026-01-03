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
    
    enum AIError: Error {
        case modelNotAvailable
        case sessionCreationFailed
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
        let availability = await newModel.availability
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
        let session: LanguageModelSession
        do {
            session = try LanguageModelSession(model: model, instructions: instructions)
            print("DEBUG SWIFT: Fresh session created.")
        } catch {
            print("DEBUG SWIFT: Failed to create session: \(error.localizedDescription)")
            throw AIError.sessionCreationFailed
        }
        
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
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

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
        
        Task {
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
                result(FlutterError(code: "UNSUPPORTED", message: "MacOS 15+ required", details: nil))
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
      } else if call.method == "playVideo" {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Path argument missing", details: nil))
          return
        }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
