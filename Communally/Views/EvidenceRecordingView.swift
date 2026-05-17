//
//  EvidenceRecordingView.swift
//  Communally
//
//  UI for audio/video recording during jobs
//

import SwiftUI
import AVKit

// MARK: - Evidence Recording Control Panel

struct EvidenceRecordingPanel: View {
    let jobId: String
    let userId: String
    @ObservedObject var recordingService = EvidenceRecordingService.shared
    @State private var showRecordingOptions = false
    @State private var showRecordings = false
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                // Expanded View
                VStack(spacing: 16) {
                    // Header
                    HStack {
                        Image(systemName: "shield.checkered")
                            .font(.title3)
                            .foregroundColor(.blue)
                        
                        Text("Evidence Recording")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button(action: { isExpanded = false }) {
                            Image(systemName: "chevron.down")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Recording Status
                    if recordingService.recordingStatus == .recording {
                        RecordingStatusView()
                    }
                    
                    // Action Buttons
                    if recordingService.recordingStatus == .idle {
                        HStack(spacing: 12) {
                            RecordButton(
                                icon: "mic.fill",
                                title: "Audio",
                                color: .blue,
                                action: {
                                    recordingService.startAudioRecording(jobId: jobId, userId: userId)
                                }
                            )
                            
                            RecordButton(
                                icon: "video.fill",
                                title: "Video",
                                color: .red,
                                action: {
                                    recordingService.startVideoRecording(jobId: jobId, userId: userId)
                                }
                            )
                            
                            RecordButton(
                                icon: "camera.fill",
                                title: "Photo",
                                color: .green,
                                action: {
                                    recordingService.capturePhoto(jobId: jobId, userId: userId) { _ in }
                                }
                            )
                        }
                    } else if recordingService.recordingStatus == .recording {
                        HStack(spacing: 12) {
                            Button(action: {
                                if recordingService.currentRecording?.type == .audio {
                                    recordingService.pauseAudioRecording()
                                }
                            }) {
                                Label("Pause", systemImage: "pause.fill")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.orange)
                                    .cornerRadius(12)
                            }
                            
                            Button(action: {
                                if recordingService.currentRecording?.type == .audio {
                                    recordingService.stopAudioRecording()
                                } else {
                                    recordingService.stopVideoRecording()
                                }
                            }) {
                                Label("Stop", systemImage: "stop.fill")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.red)
                                    .cornerRadius(12)
                            }
                        }
                    } else if recordingService.recordingStatus == .paused {
                        Button(action: {
                            recordingService.resumeAudioRecording()
                        }) {
                            Label("Resume Recording", systemImage: "play.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(12)
                        }
                    }
                    
                    // View Recordings Button
                    Button(action: { showRecordings = true }) {
                        HStack {
                            Image(systemName: "folder.fill")
                            Text("View Recordings (\(recordingService.getRecordings(for: jobId).count))")
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding()
                .background(
                    LinearGradient(
                        colors: [Color(UIColor.systemBackground), Color.blue.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
                .padding()
            } else {
                // Collapsed View (Floating Button)
                Button(action: { isExpanded = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: recordingService.recordingStatus == .recording ? "record.circle.fill" : "shield.checkered")
                            .font(.title3)
                        
                        if recordingService.recordingStatus == .recording {
                            Text(formatDuration(recordingService.recordingDuration))
                                .font(.headline)
                                .monospacedDigit()
                        } else {
                            Text("Evidence")
                                .font(.headline)
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        recordingService.recordingStatus == .recording ? 
                            Color.red : Color.blue
                    )
                    .cornerRadius(25)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                }
                .padding()
            }
        }
        .sheet(isPresented: $showRecordings) {
            RecordingsListView(jobId: jobId)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Recording Status View

struct RecordingStatusView: View {
    @ObservedObject var recordingService = EvidenceRecordingService.shared
    @State private var isPulsing = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Recording Indicator
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .scaleEffect(isPulsing ? 1.2 : 1.0)
                .opacity(isPulsing ? 0.5 : 1.0)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
            
            // Type & Duration
            VStack(alignment: .leading, spacing: 4) {
                Text(recordingService.currentRecording?.type.rawValue ?? "Recording")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(formatDuration(recordingService.recordingDuration))
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundColor(.red)
            }
            
            Spacer()
            
            // File Size (estimated)
            VStack(alignment: .trailing, spacing: 4) {
                Text("Size")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(estimatedSize())
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
        .onAppear {
            isPulsing = true
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func estimatedSize() -> String {
        // Rough estimate: audio ~1MB/min, video ~10MB/min
        let mbPerMin: Double = recordingService.currentRecording?.type == .video ? 10.0 : 1.0
        let estimatedMB = (recordingService.recordingDuration / 60.0) * mbPerMin
        
        if estimatedMB < 1 {
            return String(format: "%.0f KB", estimatedMB * 1024)
        } else {
            return String(format: "%.1f MB", estimatedMB)
        }
    }
}

// MARK: - Record Button Component

struct RecordButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [color, color.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .cornerRadius(12)
        }
    }
}

// MARK: - Recordings List View

struct RecordingsListView: View {
    let jobId: String
    @ObservedObject var recordingService = EvidenceRecordingService.shared
    @State private var selectedRecording: EvidenceRecording?
    @State private var showSettings = false
    @Environment(\.dismiss) private var dismiss
    
    var recordings: [EvidenceRecording] {
        recordingService.getRecordings(for: jobId).sorted(by: { $0.timestamp > $1.timestamp })
    }
    
    var body: some View {
        NavigationView {
            List {
                if recordings.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "folder")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No Recordings Yet")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("Record audio, video, or take photos during the job for evidence")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(recordings) { recording in
                        Button(action: {
                            selectedRecording = recording
                        }) {
                            RecordingRowView(recording: recording)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                recordingService.deleteRecording(recording)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            
                            if recording.type == .video || recording.type == .photo {
                                Button {
                                    recordingService.saveRecordingToPhotos(recording) { _ in }
                                } label: {
                                    Label("Save", systemImage: "square.and.arrow.down")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Evidence Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(item: $selectedRecording) { recording in
                RecordingDetailView(recording: recording)
            }
            .sheet(isPresented: $showSettings) {
                RecordingSettingsView()
            }
        }
    }
}

// MARK: - Recording Row View

struct RecordingRowView: View {
    let recording: EvidenceRecording
    
    var body: some View {
        HStack(spacing: 12) {
            // Type Icon
            ZStack {
                Circle()
                    .fill(typeColor.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: recording.type.icon)
                    .font(.title3)
                    .foregroundColor(typeColor)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.type.rawValue)
                    .font(.headline)
                
                if recording.type != .photo {
                    Text(recording.formattedDuration)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text(recording.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Size & Cloud Status
            VStack(alignment: .trailing, spacing: 4) {
                Text(recording.formattedSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if recording.isUploaded {
                    Image(systemName: "icloud.fill")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private var typeColor: Color {
        switch recording.type {
        case .audio: return .blue
        case .video: return .red
        case .photo: return .green
        }
    }
}

// MARK: - Recording Detail View

struct RecordingDetailView: View {
    let recording: EvidenceRecording
    @ObservedObject var recordingService = EvidenceRecordingService.shared
    @State private var isPlaying = false
    @State private var notes = ""
    @State private var showShareSheet = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Type Icon
                    ZStack {
                        Circle()
                            .fill(typeColor.opacity(0.2))
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: recording.type.icon)
                            .font(.system(size: 50))
                            .foregroundColor(typeColor)
                    }
                    .padding(.top)
                    
                    // Details
                    VStack(spacing: 12) {
                        SimpleDetailRow(label: "Type", value: recording.type.rawValue)
                        
                        if recording.type != .photo {
                            SimpleDetailRow(label: "Duration", value: recording.formattedDuration)
                        }
                        
                        SimpleDetailRow(label: "File Size", value: recording.formattedSize)
                        SimpleDetailRow(label: "Date & Time", value: recording.formattedDate)
                        
                        if recording.isUploaded {
                            HStack {
                                Image(systemName: "icloud.fill")
                                    .foregroundColor(.blue)
                                Text("Backed up to cloud")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Playback (Audio only)
                    if recording.type == .audio {
                        Button(action: {
                            if isPlaying {
                                recordingService.stopPlayback()
                                isPlaying = false
                            } else {
                                recordingService.playRecording(recording)
                                isPlaying = true
                            }
                        }) {
                            HStack {
                                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                                Text(isPlaying ? "Stop Playback" : "Play Recording")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isPlaying ? Color.red : Color.blue)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Notes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (Optional)")
                            .font(.headline)
                        
                        TextEditor(text: $notes)
                            .foregroundColor(.black)
                            .scrollContentBackground(.hidden)
                            .frame(height: 100)
                            .padding(8)
                            .background(Color(red: 0.93, green: 0.93, blue: 0.93))
                            .cornerRadius(8)
                        
                        Button("Save Notes") {
                            recordingService.addNotes(to: recording.id, notes: notes)
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    }
                    .padding()
                    
                    // Actions
                    VStack(spacing: 12) {
                        if recording.type == .video || recording.type == .photo {
                            Button(action: {
                                recordingService.saveRecordingToPhotos(recording) { success in
                                    if success {
                                        // Show success message
                                    }
                                }
                            }) {
                                Label("Save to Photos", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(12)
                            }
                        }
                        
                        Button(action: { showShareSheet = true }) {
                            Label("Share Recording", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green.opacity(0.1))
                                .foregroundColor(.green)
                                .cornerRadius(12)
                        }
                        
                        Button(role: .destructive, action: {
                            recordingService.deleteRecording(recording)
                            dismiss()
                        }) {
                            Label("Delete Recording", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(12)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Recording Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                notes = recording.notes ?? ""
            }
        }
    }
    
    private var typeColor: Color {
        switch recording.type {
        case .audio: return .blue
        case .video: return .red
        case .photo: return .green
        }
    }
}

// MARK: - Recording Settings View

struct RecordingSettingsView: View {
    @ObservedObject var recordingService = EvidenceRecordingService.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("Auto-Start Recording on Job Accept", isOn: $recordingService.autoStartRecording)
                    
                    Picker("Recording Quality", selection: $recordingService.recordingQuality) {
                        ForEach(EvidenceRecordingService.RecordingQuality.allCases, id: \.self) { quality in
                            Text(quality.rawValue).tag(quality)
                        }
                    }
                    
                    Toggle("Auto-Save Videos to Photos", isOn: $recordingService.autoSaveToPhotos)
                } header: {
                    Text("Recording Settings")
                } footer: {
                    Text("These settings control how evidence recordings work")
                }
                
                Section {
                    InfoRow(icon: "🎙️", title: "Audio", description: "Clear voice recording")
                    InfoRow(icon: "🎥", title: "Video", description: "Visual evidence with audio")
                    InfoRow(icon: "📸", title: "Photo", description: "Quick snapshots")
                } header: {
                    Text("Recording Types")
                }
                
                Section {
                    InfoRow(icon: "🔒", title: "Storage", description: "Local device only")
                    InfoRow(icon: "⏱", title: "Max Duration", description: "1 hour per recording")
                    InfoRow(icon: "📱", title: "Quality", description: recordingService.recordingQuality.rawValue)
                } header: {
                    Text("Information")
                }
                
                Section {
                    Text("Recordings are stored securely on your device and can be used as evidence in case of disputes. You have full control over when to record and what to share.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Privacy & Security")
                }
            }
            .navigationTitle("Recording Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Simple Detail Row Component

private struct SimpleDetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}
