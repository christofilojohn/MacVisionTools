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

// Views.swift
// Mode-specific SwiftUI views

import SwiftUI

// MARK: - Emotion Vibes View
struct EmotionVibesView: View {
    @ObservedObject var state: EmotionVibesState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EMOTION VIBES").font(.caption2).foregroundColor(.secondary)
            
            if !state.currentEmotion.isEmpty {
                HStack {
                    Circle()
                        .fill(EmotionClasses.color(for: state.currentEmotion))
                        .frame(width: 24, height: 24)
                    Text(state.currentEmotion.capitalized)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(Int(state.currentConfidence * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(EmotionClasses.color(for: state.currentEmotion).opacity(0.2))
                .cornerRadius(8)
            } else {
                HStack {
                    Image(systemName: "face.dashed")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Waiting for face...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            
            if !state.recentEmotions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(state.recentEmotions.suffix(12), id: \.timestamp) { r in
                            Circle()
                                .fill(EmotionClasses.color(for: r.emotion))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
        }.padding(8).background(Color.pink.opacity(0.1)).cornerRadius(8)
    }
}

// MARK: - Privacy Guard View
struct PrivacyGuardView: View {
    @ObservedObject var state: PrivacyGuardState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRIVACY GUARD").font(.caption2).foregroundColor(.secondary)
            HStack {
                Toggle("Armed", isOn: $state.isArmed).toggleStyle(.switch).controlSize(.small)
                Spacer()
                Text("People: \(state.personCount)").font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(state.personCount >= state.lockThreshold ? Color.red.opacity(0.3) : Color.green.opacity(0.3)).cornerRadius(4)
            }
            HStack { Text("Protect at:").font(.caption); Stepper("\(state.lockThreshold) people", value: $state.lockThreshold, in: 2...5).font(.caption) }
            Text("Starts the screen saver. Turn on \"Require password immediately after screen saver begins\" in macOS settings for locking.")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            if state.hasTriggeredLock {
                HStack {
                    Image(systemName: "lock.fill").foregroundColor(.red)
                    Text(state.lastSecureActionMessage.isEmpty ? "Screen saver triggered" : state.lastSecureActionMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }.padding(8).background(Color.red.opacity(0.1)).cornerRadius(8)
    }
}

// MARK: - Focus Timer View (Native face tracking only)
struct FocusTimerView: View {
    @ObservedObject var state: FocusTimerState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FOCUS TIMER").font(.caption2).foregroundColor(.secondary)
            
            // Native tracking info
            HStack {
                Image(systemName: "face.smiling").foregroundColor(.blue)
                VStack(alignment: .leading) {
                    Text("Native Face Tracking").font(.caption).fontWeight(.medium)
                    Text("Tracks head pose - no model required").font(.system(size: 9)).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(6)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(6)
            
            // Sensitivity slider
            HStack {
                Text("Sensitivity:").font(.caption)
                Slider(value: $state.lookAwayThreshold, in: 10...45, step: 5)
                Text("\(Int(state.lookAwayThreshold))°").font(.caption).frame(width: 30)
            }
            
            // Timer display
            HStack {
                Text(state.formattedTime)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(state.isCurrentlyFocused ? .green : .orange)
                Spacer()
                VStack(alignment: .trailing) {
                    Text("/ \(Int(state.targetTime / 60)) min").font(.caption).foregroundColor(.secondary)
                    if state.isTimerRunning {
                        HStack(spacing: 4) {
                            Circle().fill(state.isCurrentlyFocused ? Color.green : Color.orange).frame(width: 8, height: 8)
                            Text(state.isCurrentlyFocused ? "Focused" : "Distracted").font(.caption2)
                        }
                    }
                }
            }
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.gray.opacity(0.2))
                    Rectangle().fill(state.isComplete ? Color.green : Color.blue)
                        .frame(width: geo.size.width * CGFloat(state.progress))
                }
            }.frame(height: 8).cornerRadius(4)
            
            // Distraction reason
            if state.showDistractedOverlay && !state.distractionReason.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(state.distractionReason).font(.caption).foregroundColor(.orange)
                }
                .padding(6)
                .background(Color.orange.opacity(0.2))
                .cornerRadius(6)
            }
            
            // Target time buttons
            HStack {
                Text("Target:").font(.caption)
                ForEach([15, 25, 45, 60], id: \.self) { m in
                    Button("\(m)m") { state.targetTime = TimeInterval(m * 60) }
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(state.targetTime == TimeInterval(m * 60) ? Color.blue : Color.gray.opacity(0.2))
                        .foregroundColor(state.targetTime == TimeInterval(m * 60) ? .white : .primary)
                        .cornerRadius(4)
                        .buttonStyle(.plain)
                }
            }
            
            if state.isComplete {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Goal reached! 🎉").font(.caption).fontWeight(.medium)
                }
            }
        }.padding(8).background(Color.blue.opacity(0.1)).cornerRadius(8)
    }
}
