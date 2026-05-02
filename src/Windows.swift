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

// Windows.swift
// Overlay and Detection Window classes

import SwiftUI
import AppKit

// MARK: - Overlay Window
class OverlayWindow: NSWindow {
    private var detections: [Detection] = []
    private var isFromCamera = false
    
    init() {
        super.init(contentRect: NSScreen.main?.frame ?? .zero, styleMask: .borderless, backing: .buffered, defer: false)
        level = .floating; backgroundColor = .clear; isOpaque = false; ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = OverlayView()
    }
    
    func updateDetections(_ d: [Detection], isFromCamera: Bool = false) {
        detections = d
        self.isFromCamera = isFromCamera
        (contentView as? OverlayView)?.detections = d
        (contentView as? OverlayView)?.isFromCamera = isFromCamera
        contentView?.needsDisplay = true
    }
}

// MARK: - Overlay View
class OverlayView: NSView {
    var detections: [Detection] = []
    var isFromCamera = false
    
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        for d in detections {
            var rect = CGRect(x: d.boundingBox.minX * bounds.width, y: d.boundingBox.minY * bounds.height,
                             width: d.boundingBox.width * bounds.width, height: d.boundingBox.height * bounds.height)
            if isFromCamera { rect.origin.x = bounds.width - rect.maxX }
            
            ctx.setStrokeColor(d.color.cgColor); ctx.setLineWidth(2); ctx.stroke(rect)
            let label = "\(d.className) \(Int(d.confidence * 100))%"
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.white, .backgroundColor: d.color.withAlphaComponent(0.7)]
            NSAttributedString(string: label, attributes: attrs).draw(at: CGPoint(x: rect.minX, y: rect.maxY + 2))
        }
    }
}

// MARK: - Detection Window Controller
class DetectionWindowController: NSWindowController {
    private var dv: DetectionView?
    
    init() {
        let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 640, height: 480), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Vision Detection"; w.minSize = NSSize(width: 320, height: 240)
        super.init(window: w); dv = DetectionView(); w.contentView = dv
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    func showWindowed() { window?.makeKeyAndOrderFront(nil) }
    
    func updateContent(detections: [Detection], frame: CGImage?, isFromCamera: Bool) {
        dv?.detections = detections; dv?.currentFrame = frame; dv?.isFromCamera = isFromCamera; dv?.needsDisplay = true
    }
}

// MARK: - Detection View
class DetectionView: NSView {
    var detections: [Detection] = []
    var currentFrame: CGImage?
    var isFromCamera = false
    
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NSColor.black.setFill(); ctx.fill(bounds)
        
        if let frame = currentFrame {
            let fa = CGFloat(frame.width) / CGFloat(frame.height), va = bounds.width / bounds.height
            var dr: CGRect
            if fa > va { let h = bounds.width / fa; dr = CGRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h) }
            else { let w = bounds.height * fa; dr = CGRect(x: (bounds.width - w) / 2, y: 0, width: w, height: bounds.height) }
            
            if isFromCamera {
                ctx.saveGState()
                ctx.translateBy(x: dr.midX, y: 0)
                ctx.scaleBy(x: -1, y: 1)
                ctx.translateBy(x: -dr.midX, y: 0)
                ctx.draw(frame, in: dr)
                ctx.restoreGState()
            } else {
                ctx.draw(frame, in: dr)
            }
            
            for d in detections {
                var rect = CGRect(x: dr.minX + d.boundingBox.minX * dr.width,
                                 y: dr.minY + d.boundingBox.minY * dr.height,
                                 width: d.boundingBox.width * dr.width,
                                 height: d.boundingBox.height * dr.height)
                if isFromCamera {
                    rect.origin.x = dr.maxX - (d.boundingBox.minX * dr.width) - rect.width
                }
                
                ctx.setStrokeColor(d.color.cgColor); ctx.setLineWidth(2); ctx.stroke(rect)
                
                let label = "\(d.className) \(Int(d.confidence * 100))%"
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.white]
                let sz = label.size(withAttributes: attrs)
                let lr = CGRect(x: rect.minX, y: rect.maxY, width: sz.width + 8, height: sz.height + 4)
                ctx.setFillColor(d.color.withAlphaComponent(0.8).cgColor); ctx.fill(lr)
                label.draw(at: CGPoint(x: lr.minX + 4, y: lr.minY + 2), withAttributes: attrs)
            }
        } else {
            let t = "No video feed"; let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.gray]
            let s = t.size(withAttributes: a); t.draw(at: CGPoint(x: (bounds.width - s.width) / 2, y: (bounds.height - s.height) / 2), withAttributes: a)
        }
    }
}
