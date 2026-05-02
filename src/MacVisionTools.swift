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

// MacVisionTools.swift
// App entry point and AppDelegate

import SwiftUI

@main
struct MacVisionToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var detectionManager: DetectionManager!
    var overlayWindow: OverlayWindow?
    var detectionWindowController: DetectionWindowController?
    var currentDisplayMode: DisplayMode = .window
    
    var emotionState = EmotionVibesState()
    var focusState = FocusTimerState()
    var privacyState = PrivacyGuardState()
    var modelPaths = ModelPathStorage()
    @Published var currentAppMode: AppMode = .standard
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "eye.circle", accessibilityDescription: "Vision")
            button.action = #selector(togglePopover); button.target = self
        }
        
        detectionManager = DetectionManager()
        detectionManager.focusState = focusState
        detectionManager.currentAppMode = currentAppMode
        detectionManager.onDetectionsUpdated = { [weak self] detections, frame, isFromCamera in
            DispatchQueue.main.async {
                self?.handleDetections(detections)
                self?.overlayWindow?.updateDetections(detections, isFromCamera: isFromCamera)
                self?.detectionWindowController?.updateContent(detections: detections, frame: frame, isFromCamera: isFromCamera)
            }
        }
        
        overlayWindow = OverlayWindow()
        detectionWindowController = DetectionWindowController()
        
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 320, height: 560)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: ControlPanelView(
                manager: detectionManager, emotionState: emotionState, focusState: focusState,
                privacyState: privacyState, modelPaths: modelPaths, appDelegate: self,
                onDisplayModeChanged: { [weak self] mode in self?.handleDisplayModeChange(mode) },
                onSourceChanged: { [weak self] source, rate in self?.handleSourceChange(source, refreshRate: rate) }
            )
        )
        
        // Auto-load bundled model for default mode
        if let bundled = BundledModel.suggested(for: currentAppMode),
           !modelPaths.isUsingCustom(for: currentAppMode),
           let url = bundled.bundleURL {
            Task { await detectionManager.loadModel(from: url) }
        }
    }
    
    private func handleDetections(_ detections: [Detection]) {
        let filtered = detections.filter { d in !ignoredClasses.contains(where: { $0.lowercased() == d.className.lowercased() }) }
        
        switch currentAppMode {
        case .standard: break
        case .emotionVibes:
            if let top = filtered.first {
                emotionState.recordEmotion(top.className, confidence: top.confidence)
            }
        case .privacyGuard:
            privacyState.updatePersonCount(filtered.filter { $0.className.lowercased() == "person" }.count)
        case .focusTimer:
            // Native face tracking handles this in DetectionManager
            break
        }
    }
    
    func clearModeState() {
        emotionState.clear()
        privacyState.clear()
    }
    
    func updateStatusBarIcon() {
        statusItem?.button?.image = NSImage(systemSymbolName: currentAppMode.icon, accessibilityDescription: currentAppMode.rawValue)
    }
    
    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); NSApp.activate(ignoringOtherApps: true) }
    }
    
    func handleDisplayModeChange(_ mode: DisplayMode) {
        currentDisplayMode = mode
        if mode == .overlay { detectionWindowController?.window?.orderOut(nil); overlayWindow?.orderFrontRegardless() }
        else { overlayWindow?.orderOut(nil); detectionWindowController?.showWindowed() }
    }
    
    func handleSourceChange(_ source: CaptureSource, refreshRate: RefreshRate) {
        if detectionManager.isRunning {
            detectionManager.stopDetection()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.handleDisplayModeChange(self.currentDisplayMode)
                self.detectionManager.startDetection(source: source, refreshRate: refreshRate)
            }
        }
    }
}
