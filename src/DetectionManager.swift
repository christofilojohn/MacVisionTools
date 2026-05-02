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

// DetectionManager.swift
// Handles all detection logic including camera, screen capture, and ML inference

import SwiftUI
import CoreML
import Vision
import AVFoundation
import ScreenCaptureKit
import CoreGraphics

// MARK: - Detection Manager
class DetectionManager: NSObject, ObservableObject {
    @Published var isModelLoaded = false
    @Published var isRunning = false
    @Published var confidenceThreshold: Float = 0.5
    @Published var statusMessage = ""
    @Published var detectionCount = 0
    @Published var fps: Double = 0
    @Published var isClassificationModel = false
    
    var onDetectionsUpdated: (([Detection], CGImage?, Bool) -> Void)?
    weak var focusState: FocusTimerState?
    var currentAppMode: AppMode = .standard
    
    private var visionModel: VNCoreMLModel?
    private var captureSession: AVCaptureSession?
    private var screenStream: SCStream?
    private var streamOutput: StreamOutput?
    private var isUsingCamera = false
    private var frameCounter = 0
    private var fpsTimer: Timer?
    private var lastFPSUpdate = CFAbsoluteTimeGetCurrent()
    private var currentRefreshRate: RefreshRate = .fps30
    private var lastFrameProcessTime: CFAbsoluteTime = 0
    private var modelLoadGeneration = 0
    
    private lazy var ciContext: CIContext = { CIContext(options: [.useSoftwareRenderer: false]) }()
    private let colors: [NSColor] = (0..<80).map { NSColor(hue: CGFloat($0) / 80.0, saturation: 0.8, brightness: 0.9, alpha: 1.0) }
    private let cocoClasses = ["person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat", "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat", "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack", "umbrella", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball", "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket", "bottle", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple", "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch", "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse", "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink", "refrigerator", "book", "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush"]
    private let emotionClasses = ["neutral", "happiness", "surprise", "sadness", "anger", "disgust", "fear", "contempt"]
    private let tfCocoClassNames: [Int: String] = [
        1: "person", 2: "bicycle", 3: "car", 4: "motorcycle", 5: "airplane", 6: "bus", 7: "train", 8: "truck", 9: "boat", 10: "traffic light", 11: "fire hydrant", 13: "stop sign", 14: "parking meter", 15: "bench", 16: "bird", 17: "cat", 18: "dog", 19: "horse", 20: "sheep", 21: "cow", 22: "elephant", 23: "bear", 24: "zebra", 25: "giraffe", 27: "backpack", 28: "umbrella", 31: "handbag", 32: "tie", 33: "suitcase", 34: "frisbee", 35: "skis", 36: "snowboard", 37: "sports ball", 38: "kite", 39: "baseball bat", 40: "baseball glove", 41: "skateboard", 42: "surfboard", 43: "tennis racket", 44: "bottle", 46: "wine glass", 47: "cup", 48: "fork", 49: "knife", 50: "spoon", 51: "bowl", 52: "banana", 53: "apple", 54: "sandwich", 55: "orange", 56: "broccoli", 57: "carrot", 58: "hot dog", 59: "pizza", 60: "donut", 61: "cake", 62: "chair", 63: "couch", 64: "potted plant", 65: "bed", 67: "dining table", 70: "toilet", 72: "tv", 73: "laptop", 74: "mouse", 75: "remote", 76: "keyboard", 77: "cell phone", 78: "microwave", 79: "oven", 80: "toaster", 81: "sink", 82: "refrigerator", 84: "book", 85: "clock", 86: "vase", 87: "scissors", 88: "teddy bear", 89: "hair drier", 90: "toothbrush"
    ]
    
    @MainActor func loadModel(from url: URL) async {
        modelLoadGeneration += 1
        let generation = modelLoadGeneration
        visionModel = nil
        isModelLoaded = false
        isClassificationModel = false
        statusMessage = "Loading..."
        do {
            var modelURL = url
            if ["mlpackage", "mlmodel"].contains(url.pathExtension.lowercased()) {
                statusMessage = "Compiling..."
                modelURL = try await Task.detached { try MLModel.compileModel(at: url) }.value
            }
            let config = MLModelConfiguration(); config.computeUnits = .all
            let mlModel = try await Task.detached { try MLModel(contentsOf: modelURL, configuration: config) }.value
            guard generation == modelLoadGeneration else { return }
            visionModel = try VNCoreMLModel(for: mlModel)
            let desc = mlModel.modelDescription
            isClassificationModel = desc.predictedFeatureName != nil && desc.outputDescriptionsByName.count <= 2
            isModelLoaded = true
            statusMessage = isClassificationModel ? "Classification model" : "Detection model"
        } catch {
            guard generation == modelLoadGeneration else { return }
            visionModel = nil
            statusMessage = "Error: \(error.localizedDescription)"
            isModelLoaded = false
            isClassificationModel = false
        }
    }
    
    @discardableResult
    func startDetection(source: CaptureSource, refreshRate: RefreshRate = .fps30) -> Bool {
        // Focus Timer always works (native tracking), others need model
        guard !isRunning else { return true }
        if currentAppMode != .focusTimer && !isModelLoaded {
            statusMessage = "Load a model before starting"
            return false
        }
        isRunning = true; frameCounter = 0; lastFPSUpdate = CFAbsoluteTimeGetCurrent(); currentRefreshRate = refreshRate; isUsingCamera = source == .camera
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.updateFPS() }
        if source == .screen {
            startScreenCapture()
            return true
        } else if let failure = startCameraCapture() {
            failCaptureStart(failure)
            return false
        }
        return true
    }
    
    func stopDetection() {
        isRunning = false
        fpsTimer?.invalidate()
        fpsTimer = nil
        
        // Stop screen capture
        if let stream = screenStream {
            stream.stopCapture { _ in }
        }
        screenStream = nil
        streamOutput = nil
        
        // Stop camera
        if let session = captureSession {
            session.stopRunning()
        }
        captureSession = nil
        
        DispatchQueue.main.async {
            self.fps = 0
            self.detectionCount = 0
            self.statusMessage = "Stopped"
            self.onDetectionsUpdated?([], nil, false)
        }
    }
    
    private func updateFPS() {
        let now = CFAbsoluteTimeGetCurrent(); let elapsed = now - lastFPSUpdate
        if elapsed > 0 { DispatchQueue.main.async { self.fps = Double(self.frameCounter) / elapsed } }
        frameCounter = 0; lastFPSUpdate = now
    }
    
    private func startScreenCapture() {
        statusMessage = "Starting screen..."
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            failCaptureStart("Screen Recording permission required. Enable it in System Settings > Privacy & Security > Screen Recording, then restart Mac Vision Tools.")
            return
        }

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else {
                    failCaptureStart("No display")
                    return
                }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = display.width; config.height = display.height
                config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(currentRefreshRate.targetFPS))
                config.queueDepth = 3; config.showsCursor = false; config.pixelFormat = kCVPixelFormatType_32BGRA
                streamOutput = StreamOutput { [weak self] frame in self?.processFrame(frame, isFromCamera: false) }
                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                try stream.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
                try await stream.startCapture(); screenStream = stream
                guard isRunning else {
                    try? await stream.stopCapture()
                    return
                }
                await MainActor.run { statusMessage = "Screen capture running" }
            } catch { failCaptureStart("Screen failed: \(error.localizedDescription)") }
        }
    }
    
    private func startCameraCapture() -> String? {
        statusMessage = "Starting camera..."
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            statusMessage = "Waiting for Camera permission..."
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.isRunning else { return }
                    if granted {
                        if let failure = self.startCameraCapture() {
                            self.failCaptureStart(failure)
                        }
                    } else {
                        self.failCaptureStart("Camera permission required. Enable it in System Settings > Privacy & Security > Camera.")
                    }
                }
            }
            return nil
        case .denied, .restricted:
            return "Camera permission required. Enable it in System Settings > Privacy & Security > Camera."
        @unknown default:
            return "Camera permission unavailable"
        }

        let session = AVCaptureSession(); session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device) else { return "No camera" }
        guard session.canAddInput(input) else { return "Camera input unavailable" }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: .global(qos: .userInteractive))
        guard session.canAddOutput(output) else { return "Camera output unavailable" }
        session.addOutput(output)
        captureSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
            DispatchQueue.main.async {
                if self.isRunning {
                    self.statusMessage = session.isRunning ? "Camera running" : "Camera failed to start"
                    if !session.isRunning { self.failCaptureStart("Camera failed to start") }
                }
            }
        }
        return nil
    }
    
    private func failCaptureStart(_ message: String) {
        DispatchQueue.main.async {
            self.isRunning = false
            self.fpsTimer?.invalidate()
            self.fpsTimer = nil
            self.captureSession = nil
            self.screenStream = nil
            self.streamOutput = nil
            self.fps = 0
            self.detectionCount = 0
            self.statusMessage = message
            if self.currentAppMode == .focusTimer {
                self.focusState?.stopSession()
            }
            self.onDetectionsUpdated?([], nil, self.isUsingCamera)
        }
    }
    
    private func processFrame(_ image: CGImage, isFromCamera: Bool) {
        guard isRunning else {
            DispatchQueue.main.async { self.onDetectionsUpdated?([], nil, isFromCamera) }
            return
        }
        
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFrameProcessTime >= 1.0 / currentRefreshRate.targetFPS else { return }
        lastFrameProcessTime = now
        
        // Focus Timer always uses native face tracking
        if currentAppMode == .focusTimer {
            processNativeFaceTracking(image, isFromCamera: isFromCamera)
            return
        }
        
        guard let model = visionModel else { return }
        
        if isClassificationModel {
            processWithFaceDetection(image, model: model, isFromCamera: isFromCamera)
        } else {
            let request = VNCoreMLRequest(model: model) { [weak self] req, _ in
                guard let self = self else { return }
                let detections = self.parseObjectDetectionResults(req.results)
                DispatchQueue.main.async { self.frameCounter += 1; self.detectionCount = detections.count; self.onDetectionsUpdated?(detections, image, isFromCamera) }
            }
            request.imageCropAndScaleOption = .scaleFill
            try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        }
    }
    
    // MARK: - Native Face Tracking
    private func processNativeFaceTracking(_ image: CGImage, isFromCamera: Bool) {
        let faceRequest = VNDetectFaceLandmarksRequest { [weak self] request, error in
            guard let self = self, let faces = request.results as? [VNFaceObservation] else {
                DispatchQueue.main.async {
                    self?.frameCounter += 1
                    self?.detectionCount = 0
                    self?.focusState?.updateFocusState(isFocused: false, reason: "No face detected")
                    self?.onDetectionsUpdated?([], image, isFromCamera)
                }
                return
            }
            
            var detections: [Detection] = []
            var isFocused = false
            var reason = ""
            
            if let face = faces.first {
                let yaw = face.yaw?.doubleValue ?? 0
                let roll = face.roll?.doubleValue ?? 0
                let yawDegrees = abs(yaw * 180 / .pi)
                let rollDegrees = abs(roll * 180 / .pi)
                let threshold = self.focusState?.lookAwayThreshold ?? 25
                
                if yawDegrees < threshold && rollDegrees < threshold {
                    isFocused = true
                } else {
                    if yawDegrees >= threshold {
                        reason = "Looking \(yaw > 0 ? "left" : "right") (\(Int(yawDegrees))°)"
                    } else {
                        reason = "Head tilted (\(Int(rollDegrees))°)"
                    }
                }
                
                let color: NSColor = isFocused ? .systemGreen : .systemOrange
                let label = isFocused ? "Focused" : "Distracted"
                detections.append(Detection(className: label, classIndex: 0, confidence: 1.0, boundingBox: face.boundingBox, color: color))
            }
            
            DispatchQueue.main.async {
                self.frameCounter += 1
                self.detectionCount = detections.count
                self.focusState?.updateFocusState(isFocused: isFocused, reason: reason)
                self.onDetectionsUpdated?(detections, image, isFromCamera)
            }
        }
        
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([faceRequest])
    }
    
    private func processWithFaceDetection(_ image: CGImage, model: VNCoreMLModel, isFromCamera: Bool) {
        let faceRequest = VNDetectFaceRectanglesRequest { [weak self] request, error in
            guard let self = self, let faces = request.results as? [VNFaceObservation], !faces.isEmpty else {
                DispatchQueue.main.async { self?.frameCounter += 1; self?.detectionCount = 0; self?.onDetectionsUpdated?([], image, isFromCamera) }
                return
            }
            var allDetections: [Detection] = []
            let group = DispatchGroup()
            for face in faces {
                group.enter()
                let faceRect = face.boundingBox
                let imageWidth = CGFloat(image.width), imageHeight = CGFloat(image.height)
                let imageRect = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
                let cropRect = CGRect(x: faceRect.minX * imageWidth, y: (1 - faceRect.maxY) * imageHeight, width: faceRect.width * imageWidth, height: faceRect.height * imageHeight).integral.intersection(imageRect)
                guard !cropRect.isNull, cropRect.width > 0, cropRect.height > 0 else { group.leave(); continue }
                guard let croppedFace = image.cropping(to: cropRect) else { group.leave(); continue }
                let classifyRequest = VNCoreMLRequest(model: model) { [weak self] req, _ in
                    defer { group.leave() }
                    guard let self = self, let classifications = req.results as? [VNClassificationObservation], let top = classifications.first, top.confidence >= self.confidenceThreshold else { return }
                    let detection = Detection(className: top.identifier, classIndex: self.emotionClasses.firstIndex(of: top.identifier.lowercased()) ?? 0, confidence: top.confidence, boundingBox: faceRect, color: self.colorForEmotion(top.identifier))
                    allDetections.append(detection)
                }
                classifyRequest.imageCropAndScaleOption = .scaleFill
                try? VNImageRequestHandler(cgImage: croppedFace, options: [:]).perform([classifyRequest])
            }
            group.notify(queue: .main) { self.frameCounter += 1; self.detectionCount = allDetections.count; self.onDetectionsUpdated?(allDetections, image, isFromCamera) }
        }
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([faceRequest])
    }
    
    private func colorForEmotion(_ emotion: String) -> NSColor {
        let e = emotion.lowercased()
        switch e {
        case "happiness", "happy": return .systemGreen
        case "surprise": return .systemYellow
        case "neutral": return .systemGray
        case "sadness", "sad": return .systemBlue
        case "anger", "angry": return .systemRed
        case "fear": return .systemPurple
        case "disgust": return .brown
        case "contempt": return .systemOrange
        default: return .systemGray
        }
    }
    
    private func parseObjectDetectionResults(_ results: [Any]?) -> [Detection] {
        guard let results = results else { return [] }
        let recognizedObjects = results.compactMap { r -> Detection? in
            guard let obs = r as? VNRecognizedObjectObservation, obs.confidence >= confidenceThreshold else { return nil }
            let name = obs.labels.first?.identifier ?? "unknown"
            let idx = cocoClasses.firstIndex(of: name.lowercased()) ?? abs(name.hashValue) % 80
            return Detection(className: name, classIndex: idx, confidence: obs.confidence, boundingBox: obs.boundingBox, color: colors[idx % colors.count])
        }
        if !recognizedObjects.isEmpty { return recognizedObjects }
        return parseFeatureValueDetectionResults(results)
    }
    
    private func parseFeatureValueDetectionResults(_ results: [Any]) -> [Detection] {
        let observations = results.compactMap { $0 as? VNCoreMLFeatureValueObservation }
        guard !observations.isEmpty else { return [] }
        
        let features = Dictionary(uniqueKeysWithValues: observations.map { ($0.featureName.lowercased(), $0.featureValue) })
        
        if let boxes = featureValue(in: features, matching: ["detection_boxes", "boxes"])?.multiArrayValue,
           let scores = featureValue(in: features, matching: ["detection_scores", "scores"])?.multiArrayValue,
           let classes = featureValue(in: features, matching: ["detection_classes", "classes"])?.multiArrayValue {
            let count = detectionCount(features: features, fallback: min(boxes.count / 4, min(scores.count, classes.count)))
            return parseTensorFlowSSDResults(boxes: boxes, scores: scores, classes: classes, count: count)
        }

        if let rawBoxes = featureValue(in: features, matching: ["raw_detection_boxes", "identity_6"])?.multiArrayValue,
           let rawScores = featureValue(in: features, matching: ["raw_detection_scores", "identity_7"])?.multiArrayValue {
            return parseRawTensorFlowSSDResults(boxes: rawBoxes, scores: rawScores)
        }
        
        if let coordinates = featureValue(in: features, matching: ["coordinates"])?.multiArrayValue,
           let confidence = featureValue(in: features, matching: ["confidence"])?.multiArrayValue {
            return parseCoreMLNMSResults(coordinates: coordinates, confidence: confidence)
        }
        
        return []
    }
    
    private func featureValue(in features: [String: MLFeatureValue], matching names: [String]) -> MLFeatureValue? {
        for name in names {
            if let exact = features[name] { return exact }
            if let match = features.first(where: { $0.key.contains(name) })?.value { return match }
        }
        return nil
    }
    
    private func detectionCount(features: [String: MLFeatureValue], fallback: Int) -> Int {
        guard let numDetections = featureValue(in: features, matching: ["num_detections", "numdetections"])?.multiArrayValue,
              numDetections.count > 0 else { return fallback }
        return min(fallback, max(0, Int(numDetections[0].doubleValue.rounded())))
    }
    
    private func parseTensorFlowSSDResults(boxes: MLMultiArray, scores: MLMultiArray, classes: MLMultiArray, count: Int) -> [Detection] {
        var detections: [Detection] = []
        let usableCount = min(count, boxes.count / 4, scores.count, classes.count)
        
        for i in 0..<usableCount {
            let score = Float(scores[i].doubleValue)
            guard score >= confidenceThreshold else { continue }
            
            let ymin = clampUnit(boxes[i * 4].doubleValue)
            let xmin = clampUnit(boxes[i * 4 + 1].doubleValue)
            let ymax = clampUnit(boxes[i * 4 + 2].doubleValue)
            let xmax = clampUnit(boxes[i * 4 + 3].doubleValue)
            let width = max(0, xmax - xmin)
            let height = max(0, ymax - ymin)
            guard width > 0, height > 0 else { continue }
            
            let classID = Int(classes[i].doubleValue.rounded())
            let className = tfCocoClassNames[classID] ?? cocoClassName(forZeroBasedIndex: classID - 1) ?? "class \(classID)"
            let classIndex = cocoClasses.firstIndex(of: className.lowercased()) ?? max(0, classID - 1) % colors.count
            let rect = CGRect(x: xmin, y: 1 - ymax, width: width, height: height)
            detections.append(Detection(className: className, classIndex: classIndex, confidence: score, boundingBox: rect, color: colors[classIndex % colors.count]))
        }
        
        return detections
    }
    
    private func parseCoreMLNMSResults(coordinates: MLMultiArray, confidence: MLMultiArray) -> [Detection] {
        let classCount = cocoClasses.count
        let boxCount = min(coordinates.count / 4, confidence.count / classCount)
        var detections: [Detection] = []
        
        for i in 0..<boxCount {
            var bestClass = 0
            var bestScore: Float = 0
            for classIndex in 0..<classCount {
                let score = Float(confidence[i * classCount + classIndex].doubleValue)
                if score > bestScore {
                    bestScore = score
                    bestClass = classIndex
                }
            }
            guard bestScore >= confidenceThreshold else { continue }
            
            let centerX = clampUnit(coordinates[i * 4].doubleValue)
            let centerY = clampUnit(coordinates[i * 4 + 1].doubleValue)
            let width = clampUnit(coordinates[i * 4 + 2].doubleValue)
            let height = clampUnit(coordinates[i * 4 + 3].doubleValue)
            let rect = CGRect(x: clampUnit(centerX - width / 2), y: clampUnit(centerY - height / 2), width: width, height: height)
            detections.append(Detection(className: cocoClasses[bestClass], classIndex: bestClass, confidence: bestScore, boundingBox: rect, color: colors[bestClass % colors.count]))
        }
        
        return detections
    }

    private func parseRawTensorFlowSSDResults(boxes: MLMultiArray, scores: MLMultiArray) -> [Detection] {
        let classCount = 91
        let boxCount = min(boxes.count / 4, scores.count / classCount)
        var candidates: [Detection] = []
        candidates.reserveCapacity(min(boxCount, 200))

        for i in 0..<boxCount {
            var bestClassID = 0
            var bestScore: Float = 0

            for classID in 1..<classCount {
                let score = Float(scores[i * classCount + classID].doubleValue)
                if score > bestScore {
                    bestScore = score
                    bestClassID = classID
                }
            }

            guard bestScore >= confidenceThreshold else { continue }

            let ymin = clampUnit(boxes[i * 4].doubleValue)
            let xmin = clampUnit(boxes[i * 4 + 1].doubleValue)
            let ymax = clampUnit(boxes[i * 4 + 2].doubleValue)
            let xmax = clampUnit(boxes[i * 4 + 3].doubleValue)
            let width = max(0, xmax - xmin)
            let height = max(0, ymax - ymin)
            guard width > 0, height > 0 else { continue }

            let className = tfCocoClassNames[bestClassID] ?? "class \(bestClassID)"
            let classIndex = cocoClasses.firstIndex(of: className.lowercased()) ?? max(0, bestClassID - 1) % colors.count
            let rect = CGRect(x: xmin, y: 1 - ymax, width: width, height: height)
            candidates.append(Detection(className: className, classIndex: classIndex, confidence: bestScore, boundingBox: rect, color: colors[classIndex % colors.count]))
        }

        return nonMaximumSuppression(candidates.sorted { $0.confidence > $1.confidence }, iouThreshold: 0.5, maxDetections: 100)
    }

    private func nonMaximumSuppression(_ detections: [Detection], iouThreshold: CGFloat, maxDetections: Int) -> [Detection] {
        var selected: [Detection] = []
        selected.reserveCapacity(min(maxDetections, detections.count))

        for detection in detections.prefix(300) {
            let overlapsExisting = selected.contains { existing in
                existing.className == detection.className && intersectionOverUnion(existing.boundingBox, detection.boundingBox) > iouThreshold
            }
            if !overlapsExisting {
                selected.append(detection)
                if selected.count >= maxDetections { break }
            }
        }

        return selected
    }

    private func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }
    
    private func cocoClassName(forZeroBasedIndex index: Int) -> String? {
        guard cocoClasses.indices.contains(index) else { return nil }
        return cocoClasses[index]
    }
    
    private func clampUnit(_ value: Double) -> CGFloat {
        CGFloat(min(1, max(0, value)))
    }
}

// MARK: - Camera Delegate
extension DetectionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer), let cg = ciContext.createCGImage(CIImage(cvPixelBuffer: pb), from: CIImage(cvPixelBuffer: pb).extent) else { return }
        processFrame(cg, isFromCamera: true)
    }
}

// MARK: - Screen Capture Output
class StreamOutput: NSObject, SCStreamOutput {
    var handler: (CGImage) -> Void
    init(handler: @escaping (CGImage) -> Void) { self.handler = handler }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let ib = CMSampleBufferGetImageBuffer(sampleBuffer), let cg = CIContext().createCGImage(CIImage(cvPixelBuffer: ib), from: CIImage(cvPixelBuffer: ib).extent) else { return }
        handler(cg)
    }
}
