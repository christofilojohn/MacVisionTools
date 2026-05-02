//Copyright 2026 Ioannis Christofilogiannis
//
//Licensed under the Apache License, Version 2.0 (the "License");
//you may not use this file except in compliance with the License.
//You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//Unless required by applicable law or agreed to in writing, software
//distributed under the License is distributed on an "AS IS" BASIS,
//WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//See the License for the specific language governing permissions and
//limitations under the License.

// Models.swift
// Data models, enums, and state classes

import SwiftUI
import CoreML
import AppKit

// MARK: - App Mode Enum
enum AppMode: String, CaseIterable, Codable {
    case standard = "Standard Detection"
    case emotionVibes = "Emotion Vibes"
    case privacyGuard = "Privacy Guard"
    case focusTimer = "Focus Timer"
    
    var icon: String {
        switch self {
        case .standard: return "eye.circle.fill"
        case .emotionVibes: return "face.smiling.fill"
        case .privacyGuard: return "lock.shield.fill"
        case .focusTimer: return "timer"
        }
    }
    
    var modelKey: String { "model_\(self.rawValue)" }
}

// MARK: - Bundled Models
enum BundledModel: String, CaseIterable {
    case ssdMobileNetV2 = "ssd_mobilenet_v2_320x320_raw"
    case emotieff = "emotieff"
    
    var displayName: String {
        switch self {
        case .ssdMobileNetV2: return "SSD MobileNet V2 (COCO)"
        case .emotieff: return "Emotieff (Emotion)"
        }
    }
    
    var isClassificationModel: Bool {
        switch self {
        case .ssdMobileNetV2: return false
        case .emotieff: return true
        }
    }
    
    /// Returns the URL for the bundled model
    var bundleURL: URL? {
        Bundle.main.url(forResource: rawValue, withExtension: "mlmodelc")
    }
    
    /// Suggested model for each app mode
    static func suggested(for mode: AppMode) -> BundledModel? {
        switch mode {
        case .standard: return .ssdMobileNetV2
        case .emotionVibes: return .emotieff
        case .privacyGuard: return .ssdMobileNetV2
        case .focusTimer: return nil  // Uses native face tracking
        }
    }
}

// MARK: - Other Enums
enum CaptureSource: String, CaseIterable { case screen = "Screen", camera = "Camera" }
enum DisplayMode: String, CaseIterable { case overlay = "Overlay", window = "Window" }
enum RefreshRate: String, CaseIterable {
    case fps10 = "10", fps30 = "30", fps60 = "60", unlimited = "Max"
    var targetFPS: Double {
        switch self { case .fps10: return 10; case .fps30: return 30; case .fps60: return 60; case .unlimited: return 1000 }
    }
}

// MARK: - Detection Result
struct Detection: Identifiable {
    let id = UUID()
    let className: String
    let classIndex: Int
    let confidence: Float
    let boundingBox: CGRect
    let color: NSColor
}

// MARK: - Emotion Classes
enum EmotionSentiment: String, Codable { case positive, negative, neutral }

struct EmotionClasses {
    static let ferplus: [(name: String, sentiment: EmotionSentiment)] = [
        ("neutral", .neutral), ("happiness", .positive), ("surprise", .positive),
        ("sadness", .negative), ("anger", .negative), ("disgust", .negative),
        ("fear", .negative), ("contempt", .negative)
    ]
    static let hsemotion: [(name: String, sentiment: EmotionSentiment)] = [
        ("Anger", .negative), ("Contempt", .negative), ("Disgust", .negative),
        ("Fear", .negative), ("Happiness", .positive), ("Neutral", .neutral),
        ("Sadness", .negative), ("Surprise", .positive)
    ]
    
    static func color(for emotion: String) -> Color {
        let e = emotion.lowercased()
        switch e {
        case "happiness", "happy": return .green
        case "surprise": return .yellow
        case "neutral": return .gray
        case "sadness", "sad": return .blue
        case "anger", "angry": return .red
        case "fear": return .purple
        case "disgust": return .brown
        case "contempt": return .orange
        default: return .gray
        }
    }
}

// Focus classes (for legacy model-based detection)
let ignoredClasses = ["seatbelt", "seat belt", "Seatbelt"]
let distractedClasses = ["Distracted", "distracted", "phone", "cell phone", "cellphone", "drowsy"]
let focusedClasses = ["Attentive", "attentive", "focused", "awake"]

// MARK: - Model Path Storage
class ModelPathStorage: ObservableObject {
    @Published var paths: [AppMode: String] = [:]
    @Published var useCustomModel: [AppMode: Bool] = [:]
    private var bookmarks: [AppMode: Data] = [:]
    
    private let pathsKey = "savedModelPaths"
    private let customKey = "useCustomModel"
    private let bookmarksKey = "savedModelBookmarks"
    
    init() { load() }
    
    func save() {
        let pathDict = Dictionary(uniqueKeysWithValues: paths.map { ($0.key.rawValue, $0.value) })
        UserDefaults.standard.set(pathDict, forKey: pathsKey)
        
        let customDict = Dictionary(uniqueKeysWithValues: useCustomModel.map { ($0.key.rawValue, $0.value) })
        UserDefaults.standard.set(customDict, forKey: customKey)

        let bookmarkDict = Dictionary(uniqueKeysWithValues: bookmarks.map { ($0.key.rawValue, $0.value) })
        UserDefaults.standard.set(bookmarkDict, forKey: bookmarksKey)
    }
    
    func load() {
        if let dict = UserDefaults.standard.dictionary(forKey: pathsKey) as? [String: String] {
            paths = Dictionary(uniqueKeysWithValues: dict.compactMap { k, v in
                AppMode(rawValue: k).map { ($0, v) }
            })
        }
        if let dict = UserDefaults.standard.dictionary(forKey: customKey) as? [String: Bool] {
            useCustomModel = Dictionary(uniqueKeysWithValues: dict.compactMap { k, v in
                AppMode(rawValue: k).map { ($0, v) }
            })
        }
        if let dict = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] {
            bookmarks = Dictionary(uniqueKeysWithValues: dict.compactMap { k, v in
                AppMode(rawValue: k).map { ($0, v) }
            })
        }
    }
    
    func setPath(_ path: String, for mode: AppMode) {
        paths[mode] = path
        useCustomModel[mode] = true
        save()
    }

    func setURL(_ url: URL, for mode: AppMode) {
        paths[mode] = url.path
        useCustomModel[mode] = true

        do {
            bookmarks[mode] = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            print("Could not save security-scoped bookmark for \(url.path): \(error)")
        }

        save()
    }
    
    func useBundled(for mode: AppMode) {
        useCustomModel[mode] = false
        save()
    }
    
    func getPath(for mode: AppMode) -> String? { paths[mode] }
    func isUsingCustom(for mode: AppMode) -> Bool { useCustomModel[mode] ?? false }
    
    func getModelURL(for mode: AppMode) -> URL? {
        if isUsingCustom(for: mode) {
            if let bookmark = bookmarks[mode] {
                var isStale = false
                do {
                    let url = try URL(
                        resolvingBookmarkData: bookmark,
                        options: [.withSecurityScope],
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )
                    _ = url.startAccessingSecurityScopedResource()

                    if isStale {
                        setURL(url, for: mode)
                    }

                    return url
                } catch {
                    print("Could not resolve security-scoped bookmark for \(mode.rawValue): \(error)")
                }
            }

            if let path = paths[mode] {
                let url = URL(fileURLWithPath: path)
                _ = url.startAccessingSecurityScopedResource()
                return url
            }
        }
        return BundledModel.suggested(for: mode)?.bundleURL
    }
}

// MARK: - Emotion Vibes State
class EmotionVibesState: ObservableObject {
    @Published var currentEmotion: String = ""
    @Published var currentConfidence: Float = 0
    @Published var recentEmotions: [(emotion: String, timestamp: Date)] = []
    
    func recordEmotion(_ className: String, confidence: Float) {
        currentEmotion = className
        currentConfidence = confidence
        recentEmotions.append((className, Date()))
        recentEmotions = recentEmotions.filter { $0.timestamp > Date().addingTimeInterval(-30) }
    }
    
    func clear() {
        currentEmotion = ""
        currentConfidence = 0
        recentEmotions = []
    }
    
    var dominantEmotion: String? {
        let recent = recentEmotions.filter { $0.timestamp > Date().addingTimeInterval(-5) }
        var counts: [String: Int] = [:]
        for r in recent { counts[r.emotion, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}

// MARK: - Focus Timer State (Native face tracking only)
class FocusTimerState: ObservableObject {
    @Published var totalFocusTime: TimeInterval = 0
    @Published var currentFocusTime: TimeInterval = 0
    @Published var isCurrentlyFocused = true
    @Published var targetTime: TimeInterval = 25 * 60
    @Published var isTimerRunning = false
    @Published var distractionReason = ""
    @Published var showDistractedOverlay = false
    @Published var lookAwayThreshold: Double = 25
    
    // Always use native face tracking
    var useNativeFaceTracking: Bool { true }
    
    private var focusStartTime: Date?
    
    func startSession() {
        totalFocusTime = 0
        currentFocusTime = 0
        isTimerRunning = true
        isCurrentlyFocused = true
        focusStartTime = Date()
        distractionReason = ""
        showDistractedOverlay = false
    }
    
    func stopSession() {
        isTimerRunning = false
        if isCurrentlyFocused, let start = focusStartTime {
            totalFocusTime += Date().timeIntervalSince(start)
        }
        currentFocusTime = totalFocusTime
        focusStartTime = nil
        showDistractedOverlay = false
    }
    
    func updateFocusState(isFocused: Bool, reason: String = "") {
        guard isTimerRunning else { return }
        let now = Date()
        
        if isFocused && !isCurrentlyFocused {
            focusStartTime = now
            isCurrentlyFocused = true
            distractionReason = ""
            showDistractedOverlay = false
        } else if !isFocused && isCurrentlyFocused {
            if let start = focusStartTime {
                totalFocusTime += now.timeIntervalSince(start)
            }
            currentFocusTime = totalFocusTime
            focusStartTime = nil
            isCurrentlyFocused = false
            distractionReason = reason
            showDistractedOverlay = true
        } else if isFocused, let start = focusStartTime {
            currentFocusTime = totalFocusTime + now.timeIntervalSince(start)
        } else {
            currentFocusTime = totalFocusTime
            if !reason.isEmpty { distractionReason = reason }
        }
    }
    
    var progress: Double { min(currentFocusTime / targetTime, 1.0) }
    var formattedTime: String { String(format: "%02d:%02d", Int(currentFocusTime) / 60, Int(currentFocusTime) % 60) }
    var isComplete: Bool { currentFocusTime >= targetTime }
}

// MARK: - Privacy Guard State
class PrivacyGuardState: ObservableObject {
    @Published var isArmed = false
    @Published var personCount = 0
    @Published var lockThreshold = 2
    @Published var hasTriggeredLock = false
    @Published var lastSecureActionMessage = ""
    private var cooldownActive = false
    
    func updatePersonCount(_ count: Int) {
        personCount = count
        guard isArmed, !cooldownActive, count >= lockThreshold, !hasTriggeredLock else {
            if count < lockThreshold {
                hasTriggeredLock = false
                lastSecureActionMessage = ""
            }
            return
        }
        hasTriggeredLock = true; cooldownActive = true
        lockScreen()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.cooldownActive = false }
    }
    
    func clear() {
        personCount = 0
        hasTriggeredLock = false
        lastSecureActionMessage = ""
    }
    
    private func lockScreen() {
        let screenSaverURL = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        NSWorkspace.shared.openApplication(at: screenSaverURL, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.lastSecureActionMessage = "Could not start screen saver: \(error.localizedDescription)"
                } else {
                    self?.lastSecureActionMessage = "Screen saver started. macOS password settings control locking."
                }
            }
        }
    }
}
