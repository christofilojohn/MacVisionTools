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

// ControlPanelView.swift
// Main control panel UI

import SwiftUI
import UniformTypeIdentifiers

struct ControlPanelView: View {
    @ObservedObject var manager: DetectionManager
    @ObservedObject var emotionState: EmotionVibesState
    @ObservedObject var focusState: FocusTimerState
    @ObservedObject var privacyState: PrivacyGuardState
    @ObservedObject var modelPaths: ModelPathStorage
    weak var appDelegate: AppDelegate?
    var onDisplayModeChanged: (DisplayMode) -> Void
    var onSourceChanged: (CaptureSource, RefreshRate) -> Void
    
    @State private var captureSource: CaptureSource = .camera
    @State private var displayMode: DisplayMode = .window
    @State private var refreshRate: RefreshRate = .fps30
    @State private var selectedAppMode: AppMode = .standard
    @State private var showThirdPartyNotices = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: selectedAppMode.icon).font(.title2).foregroundColor(appModeColor)
                    Text("Vision Detector").font(.headline)
                    Spacer()
                }
                Divider()
                
                // App Mode Selection
                VStack(alignment: .leading, spacing: 6) {
                    Text("APP MODE").font(.caption2).foregroundColor(.secondary)
                    ForEach(AppMode.allCases, id: \.self) { mode in
                        Button {
                            switchToMode(mode)
                        } label: {
                            HStack {
                                Image(systemName: mode.icon).frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.rawValue).font(.caption)
                                    // Show model info
                                    if mode == .focusTimer {
                                        Text("Native Face Tracking").font(.system(size: 9)).foregroundColor(.secondary)
                                    } else if modelPaths.isUsingCustom(for: mode), let path = modelPaths.getPath(for: mode) {
                                        Text("Custom: \(URL(fileURLWithPath: path).lastPathComponent)").font(.system(size: 9)).foregroundColor(.secondary)
                                    } else if let bundled = BundledModel.suggested(for: mode) {
                                        Text("Bundled: \(bundled.displayName)").font(.system(size: 9)).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedAppMode == mode { Image(systemName: "checkmark").foregroundColor(.green) }
                            }
                            .padding(.vertical, 4).padding(.horizontal, 8)
                            .background(selectedAppMode == mode ? Color.accentColor.opacity(0.2) : .clear)
                            .cornerRadius(6)
                        }.buttonStyle(.plain)
                    }
                }
                
                modeSpecificView
                Divider()
                
                // Model for current mode (not shown for Focus Timer)
                if selectedAppMode != .focusTimer {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MODEL FOR \(selectedAppMode.rawValue.uppercased())").font(.caption2).foregroundColor(.secondary)
                        
                        // Current model display
                        HStack {
                            if modelPaths.isUsingCustom(for: selectedAppMode), let path = modelPaths.getPath(for: selectedAppMode) {
                                Image(systemName: "doc.badge.gearshape")
                                Text(URL(fileURLWithPath: path).lastPathComponent).font(.caption).lineLimit(1)
                            } else if let bundled = BundledModel.suggested(for: selectedAppMode) {
                                Image(systemName: "shippingbox")
                                Text(bundled.displayName).font(.caption)
                            } else {
                                Text("No model").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        
                        // Model selection
                        HStack {
                            if let bundled = BundledModel.suggested(for: selectedAppMode) {
                                Button {
                                    modelPaths.useBundled(for: selectedAppMode)
                                    if let url = bundled.bundleURL {
                                        Task { await manager.loadModel(from: url) }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: modelPaths.isUsingCustom(for: selectedAppMode) ? "circle" : "checkmark.circle.fill")
                                        Text("Bundled")
                                    }.font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .tint(modelPaths.isUsingCustom(for: selectedAppMode) ? .secondary : .blue)
                            }
                            
                            Menu {
                                Button("Select Local File...") { selectModel() }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: modelPaths.isUsingCustom(for: selectedAppMode) ? "checkmark.circle.fill" : "circle")
                                    Text("Custom")
                                }.font(.caption)
                            }.menuStyle(.borderlessButton)
                            
                            Spacer()
                        }
                        
                        if manager.isModelLoaded {
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                Text(manager.isClassificationModel ? "Classification" : "Detection").font(.caption).foregroundColor(.green)
                            }
                        }
                    }
                    Divider()
                }
                
                // Capture settings
                VStack(alignment: .leading, spacing: 6) {
                    Text("CAPTURE").font(.caption2).foregroundColor(.secondary)
                    HStack { Text("Source").font(.caption); Spacer()
                        Picker("", selection: $captureSource) { ForEach(CaptureSource.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                            .pickerStyle(.segmented).frame(width: 140).onChange(of: captureSource) { _ in onSourceChanged(captureSource, refreshRate) }
                    }
                    HStack { Text("Display").font(.caption); Spacer()
                        Picker("", selection: $displayMode) { ForEach(DisplayMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                            .pickerStyle(.segmented).frame(width: 140).onChange(of: displayMode) { _ in onDisplayModeChanged(displayMode) }
                    }
                    HStack { Text("FPS").font(.caption); Spacer()
                        Picker("", selection: $refreshRate) { ForEach(RefreshRate.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                            .pickerStyle(.segmented).frame(width: 140).onChange(of: refreshRate) { _ in onSourceChanged(captureSource, refreshRate) }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("Confidence").font(.caption); Spacer(); Text(String(format: "%.0f%%", manager.confidenceThreshold * 100)).font(.caption).foregroundColor(.secondary) }
                    Slider(value: $manager.confidenceThreshold, in: 0.1...0.95, step: 0.05)
                }
                Divider()
                
                // Start/Stop
                Button {
                    if manager.isRunning {
                        manager.stopDetection()
                        if selectedAppMode == .focusTimer { focusState.stopSession() }
                    } else {
                        onDisplayModeChanged(displayMode)
                        if selectedAppMode == .focusTimer { focusState.startSession() }
                        let didStart = manager.startDetection(source: captureSource, refreshRate: refreshRate)
                        if !didStart && selectedAppMode == .focusTimer { focusState.stopSession() }
                    }
                } label: {
                    HStack { Image(systemName: manager.isRunning ? "stop.fill" : "play.fill"); Text(manager.isRunning ? "Stop" : "Start") }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(manager.isRunning ? .red : .green)
                .disabled(selectedAppMode != .focusTimer && !manager.isModelLoaded)
                
                if !manager.statusMessage.isEmpty { Text(manager.statusMessage).font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity) }
                if manager.isRunning {
                    HStack { HStack(spacing: 4) { Image(systemName: "square.on.square"); Text("\(manager.detectionCount)") }; Spacer()
                        HStack(spacing: 4) { Image(systemName: "speedometer"); Text(String(format: "%.1f FPS", manager.fps)) }
                    }.font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                HStack {
                    Button("Notices") { showThirdPartyNotices = true }.font(.caption).buttonStyle(.plain).foregroundColor(.blue)
                    Spacer()
                    Button("Privacy") { openPrivacyPolicy() }.font(.caption).buttonStyle(.plain).foregroundColor(.blue)
                    Button("Quit") { NSApp.terminate(nil) }.font(.caption).buttonStyle(.plain).foregroundColor(.secondary)
                }
            }.padding()
        }
        .frame(width: 300, height: 560)
        .sheet(isPresented: $showThirdPartyNotices) {
            ThirdPartyNoticesView()
        }
    }
    
    // MARK: - Mode Switching with Clean Transition
    private func switchToMode(_ mode: AppMode) {
        // Step 1: Stop detection completely
        let wasRunning = manager.isRunning
        if wasRunning {
            manager.stopDetection()
            if selectedAppMode == .focusTimer {
                focusState.stopSession()
            }
        }
        
        // Step 2: Clear displays
        appDelegate?.overlayWindow?.updateDetections([], isFromCamera: false)
        appDelegate?.detectionWindowController?.updateContent(detections: [], frame: nil, isFromCamera: false)
        appDelegate?.clearModeState()
        
        // Step 3: Update mode
        selectedAppMode = mode
        appDelegate?.currentAppMode = mode
        appDelegate?.detectionManager.currentAppMode = mode
        appDelegate?.updateStatusBarIcon()
        
        // Step 4: Load model after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if mode == .focusTimer {
                self.manager.statusMessage = "Ready (Native Face Tracking)"
            } else if let url = self.modelPaths.getModelURL(for: mode) {
                Task { await self.manager.loadModel(from: url) }
            } else if let bundled = BundledModel.suggested(for: mode), let url = bundled.bundleURL {
                Task { await self.manager.loadModel(from: url) }
            }
            
            // Step 5: Restart if was running
            if wasRunning {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.onDisplayModeChanged(self.displayMode)
                    if mode == .focusTimer {
                        self.focusState.startSession()
                    }
                    let didStart = self.manager.startDetection(source: self.captureSource, refreshRate: self.refreshRate)
                    if !didStart && mode == .focusTimer {
                        self.focusState.stopSession()
                    }
                }
            }
        }
    }
    
    @ViewBuilder var modeSpecificView: some View {
        switch selectedAppMode {
        case .standard: EmptyView()
        case .emotionVibes: EmotionVibesView(state: emotionState)
        case .privacyGuard: PrivacyGuardView(state: privacyState)
        case .focusTimer: FocusTimerView(state: focusState)
        }
    }
    
    var appModeColor: Color {
        switch selectedAppMode { case .standard: return .orange; case .emotionVibes: return .pink; case .privacyGuard: return .red; case .focusTimer: return .blue }
    }
    
    private func selectModel() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = true; panel.canChooseFiles = true
        var types: [UTType] = [.folder, .directory, .bundle, .package]
        if let t = UTType(filenameExtension: "mlmodel") { types.append(t) }
        if let t = UTType(filenameExtension: "mlpackage") { types.append(t) }
        if let t = UTType(filenameExtension: "mlmodelc") { types.append(t) }
        panel.allowedContentTypes = types
        if panel.runModal() == .OK, let url = panel.url {
            modelPaths.setURL(url, for: selectedAppMode)
            Task { await manager.loadModel(from: url) }
        }
    }

    private func openPrivacyPolicy() {
        if let url = URL(string: "https://macvisiontools.pages.dev/privacy/") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct ThirdPartyNoticesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Third-Party Notices")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Bundled models, frameworks, and license acknowledgments")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    noticeSection(
                        title: "TensorFlow SSD MobileNet V2",
                        subtitle: "Used for Standard Detection and Privacy Guard",
                        rows: [
                            ("Project", "TensorFlow Models"),
                            ("Model", "SSD MobileNet V2 320x320 trained on COCO 2017, exported to Core ML with raw detector outputs"),
                            ("Copyright", "TensorFlow Authors"),
                            ("License", "Apache License 2.0")
                        ],
                        url: "https://github.com/tensorflow/models"
                    )

                    noticeSection(
                        title: "EmotiEff AffectNet Emotion Model",
                        subtitle: "Used for Emotion Vibes facial emotion classification",
                        rows: [
                            ("Project", "EmotiEffLib"),
                            ("Source", "Sber AI Lab"),
                            ("Model", "mobilenet_7.h5 architecture and weights"),
                            ("License", "Apache License 2.0")
                        ],
                        url: "https://github.com/sb-ai-lab/EmotiEffLib"
                    )

                    noticeSection(
                        title: "Apple Vision Framework",
                        subtitle: "Used for face detection, landmarks, and native focus tracking",
                        rows: [
                            ("Provider", "Apple Inc."),
                            ("Copyright", "Apple Inc. All rights reserved.")
                        ],
                        url: "https://developer.apple.com/documentation/vision"
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom Models")
                            .font(.headline)
                        Text("Mac Vision Tools can load user-selected Core ML models from local files. Those files are not bundled with the app; users are responsible for ensuring they have permission to use and redistribute any custom models they select.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Apache License 2.0")
                            .font(.headline)
                        Text("The bundled TensorFlow and EmotiEff model notices identify Apache License 2.0 components. You may obtain the license text at apache.org/licenses/LICENSE-2.0.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Link("Open Apache License 2.0", destination: URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(8)

                    Text("The Mac Vision Tools app itself is licensed under Apache License 2.0. See the project LICENSE and CREDITS files for the full notices.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
            }
        }
        .frame(width: 560, height: 560)
    }

    private func noticeSection(title: String, subtitle: String, rows: [(String, String)], url: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let destination = URL(string: url) {
                    Link("Source", destination: destination)
                        .font(.caption)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows, id: \.0) { key, value in
                    HStack(alignment: .top, spacing: 8) {
                        Text(key)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(width: 72, alignment: .leading)
                        Text(value)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }
}
