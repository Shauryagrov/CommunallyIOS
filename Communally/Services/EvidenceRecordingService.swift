//
//  EvidenceRecordingService.swift
//  Communally
//
//  Audio/Video recording for evidence and dispute resolution
//

import Foundation
import AVFoundation
import UIKit
import Photos

// MARK: - Recording Types

enum RecordingType: String, Codable {
    case audio = "Audio"
    case video = "Video"
    case photo = "Photo"
    
    var icon: String {
        switch self {
        case .audio: return "mic.fill"
        case .video: return "video.fill"
        case .photo: return "camera.fill"
        }
    }
}

enum RecordingStatus {
    case idle
    case recording
    case paused
    case processing
    case saved
    case failed
}

// MARK: - Evidence Recording Model

struct EvidenceRecording: Identifiable, Codable {
    let id: String
    let jobId: String
    let userId: String
    let type: RecordingType
    let timestamp: Date
    let duration: TimeInterval // For audio/video
    let fileURL: String // Local path
    let fileSize: Int64 // Bytes
    let thumbnailURL: String? // For video
    let notes: String?
    let isUploaded: Bool
    let cloudURL: String? // Firebase Storage URL
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

// MARK: - Evidence Recording Service

class EvidenceRecordingService: NSObject, ObservableObject {
    static let shared = EvidenceRecordingService()
    
    // MARK: - Published Properties
    @Published var recordingStatus: RecordingStatus = .idle
    @Published var currentRecording: EvidenceRecording?
    @Published var recordings: [EvidenceRecording] = []
    @Published var isRecordingEnabled = true
    @Published var recordingDuration: TimeInterval = 0
    
    // MARK: - Private Properties
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var videoRecorder: VideoRecorder?
    private var recordingTimer: Timer?
    private var currentJobId: String?
    private var currentUserId: String?
    
    // Settings
    @Published var autoStartRecording = false
    @Published var recordingQuality: RecordingQuality = .standard
    @Published var maxRecordingDuration: TimeInterval = 3600 // 1 hour
    @Published var autoSaveToPhotos = false
    
    enum RecordingQuality: String, CaseIterable {
        case low = "Low (saves space)"
        case standard = "Standard"
        case high = "High (best quality)"
        
        var audioSettings: [String: Any] {
            switch self {
            case .low:
                return [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 22050,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
                ]
            case .standard:
                return [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ]
            case .high:
                return [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
                ]
            }
        }
    }
    
    private override init() {
        super.init()
        loadSettings()
        loadRecordings()
        setupAudioSession()
    }
    
    // MARK: - Setup
    
    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
            print("✅ Audio session configured")
        } catch {
            print("❌ Failed to configure audio session: \(error)")
        }
    }
    
    // MARK: - Permissions
    
    func requestPermissions(for type: RecordingType, completion: @escaping (Bool) -> Void) {
        switch type {
        case .audio:
            requestAudioPermission(completion: completion)
        case .video:
            requestVideoPermission(completion: completion)
        case .photo:
            requestPhotoPermission(completion: completion)
        }
    }
    
    private func requestAudioPermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                print(granted ? "✅ Audio permission granted" : "❌ Audio permission denied")
                completion(granted)
            }
        }
    }
    
    private func requestVideoPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                print(granted ? "✅ Video permission granted" : "❌ Video permission denied")
                completion(granted)
            }
        }
    }
    
    private func requestPhotoPermission(completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                let granted = status == .authorized || status == .limited
                print(granted ? "✅ Photo permission granted" : "❌ Photo permission denied")
                completion(granted)
            }
        }
    }
    
    // MARK: - Audio Recording
    
    func startAudioRecording(jobId: String, userId: String) {
        currentJobId = jobId
        currentUserId = userId
        
        requestPermissions(for: .audio) { [weak self] granted in
            guard granted else {
                print("❌ Audio permission not granted")
                return
            }
            
            self?.beginAudioRecording()
        }
    }
    
    private func beginAudioRecording() {
        let filename = generateFilename(type: .audio)
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        
        let settings = recordingQuality.audioSettings
        
        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()
            
            recordingStatus = .recording
            recordingDuration = 0
            
            startRecordingTimer()
            
            print("🎙️ Audio recording started: \(filename)")
            
            // Create recording entry
            currentRecording = EvidenceRecording(
                id: UUID().uuidString,
                jobId: currentJobId ?? "",
                userId: currentUserId ?? "",
                type: .audio,
                timestamp: Date(),
                duration: 0,
                fileURL: fileURL.path,
                fileSize: 0,
                thumbnailURL: nil,
                notes: nil,
                isUploaded: false,
                cloudURL: nil
            )
            
        } catch {
            print("❌ Failed to start audio recording: \(error)")
            recordingStatus = .failed
        }
    }
    
    func stopAudioRecording() {
        audioRecorder?.stop()
        stopRecordingTimer()
        recordingStatus = .processing
        
        print("⏹️ Audio recording stopped")
    }
    
    func pauseAudioRecording() {
        audioRecorder?.pause()
        stopRecordingTimer()
        recordingStatus = .paused
        
        print("⏸️ Audio recording paused")
    }
    
    func resumeAudioRecording() {
        audioRecorder?.record()
        startRecordingTimer()
        recordingStatus = .recording
        
        print("▶️ Audio recording resumed")
    }
    
    // MARK: - Video Recording
    
    func startVideoRecording(jobId: String, userId: String) {
        currentJobId = jobId
        currentUserId = userId
        
        requestPermissions(for: .video) { [weak self] granted in
            guard granted else {
                print("❌ Video permission not granted")
                return
            }
            
            self?.beginVideoRecording()
        }
    }
    
    private func beginVideoRecording() {
        let filename = generateFilename(type: .video)
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        
        videoRecorder = VideoRecorder(outputURL: fileURL, quality: recordingQuality)
        videoRecorder?.delegate = self
        videoRecorder?.startRecording()
        
        recordingStatus = .recording
        recordingDuration = 0
        
        startRecordingTimer()
        
        print("🎥 Video recording started: \(filename)")
        
        // Create recording entry
        currentRecording = EvidenceRecording(
            id: UUID().uuidString,
            jobId: currentJobId ?? "",
            userId: currentUserId ?? "",
            type: .video,
            timestamp: Date(),
            duration: 0,
            fileURL: fileURL.path,
            fileSize: 0,
            thumbnailURL: nil,
            notes: nil,
            isUploaded: false,
            cloudURL: nil
        )
    }
    
    func stopVideoRecording() {
        videoRecorder?.stopRecording()
        stopRecordingTimer()
        recordingStatus = .processing
        
        print("⏹️ Video recording stopped")
    }
    
    // MARK: - Photo Capture
    
    func capturePhoto(jobId: String, userId: String, completion: @escaping (Bool) -> Void) {
        currentJobId = jobId
        currentUserId = userId
        
        requestPermissions(for: .photo) { [weak self] granted in
            guard granted else {
                completion(false)
                return
            }
            
            self?.takePhoto(completion: completion)
        }
    }
    
    private func takePhoto(completion: @escaping (Bool) -> Void) {
        // This would open camera in production
        // For now, we'll create a placeholder
        print("📸 Photo captured")
        completion(true)
    }
    
    // MARK: - Playback
    
    func playRecording(_ recording: EvidenceRecording) {
        guard recording.type == .audio else {
            print("⚠️ Playback only supported for audio")
            return
        }
        
        let fileURL = URL(fileURLWithPath: recording.fileURL)
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            audioPlayer?.play()
            print("▶️ Playing recording: \(recording.id)")
        } catch {
            print("❌ Failed to play recording: \(error)")
        }
    }
    
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        print("⏹️ Playback stopped")
    }
    
    // MARK: - Recording Timer
    
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            self.recordingDuration += 1
            
            // Update current recording
            if var current = self.currentRecording {
                current = EvidenceRecording(
                    id: current.id,
                    jobId: current.jobId,
                    userId: current.userId,
                    type: current.type,
                    timestamp: current.timestamp,
                    duration: self.recordingDuration,
                    fileURL: current.fileURL,
                    fileSize: current.fileSize,
                    thumbnailURL: current.thumbnailURL,
                    notes: current.notes,
                    isUploaded: current.isUploaded,
                    cloudURL: current.cloudURL
                )
                self.currentRecording = current
            }
            
            // Auto-stop at max duration
            if self.recordingDuration >= self.maxRecordingDuration {
                print("⏱️ Max recording duration reached")
                if self.currentRecording?.type == .audio {
                    self.stopAudioRecording()
                } else {
                    self.stopVideoRecording()
                }
            }
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    // MARK: - File Management
    
    private func generateFilename(type: RecordingType) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let jobId = currentJobId ?? "unknown"
        
        switch type {
        case .audio:
            return "evidence_audio_\(jobId)_\(timestamp).m4a"
        case .video:
            return "evidence_video_\(jobId)_\(timestamp).mp4"
        case .photo:
            return "evidence_photo_\(jobId)_\(timestamp).jpg"
        }
    }
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    func deleteRecording(_ recording: EvidenceRecording) {
        let fileURL = URL(fileURLWithPath: recording.fileURL)

        do {
            try FileManager.default.removeItem(at: fileURL)
            recordings.removeAll { $0.id == recording.id }
            saveRecordings()
            print("🗑️ Recording deleted: \(recording.id)")
        } catch {
            print("❌ Failed to delete recording: \(error)")
        }
    }

    /// Hard-wipe every local recording + the saved index. Called from the
    /// account-deletion path so safety recordings don't survive a delete.
    func clearLocalState() {
        for rec in recordings {
            let fileURL = URL(fileURLWithPath: rec.fileURL)
            try? FileManager.default.removeItem(at: fileURL)
        }
        DispatchQueue.main.async {
            self.recordings = []
            self.currentRecording = nil
            self.saveRecordings()
        }
    }
    
    func saveRecordingToPhotos(_ recording: EvidenceRecording, completion: @escaping (Bool) -> Void) {
        guard recording.type == .video || recording.type == .photo else {
            completion(false)
            return
        }
        
        let fileURL = URL(fileURLWithPath: recording.fileURL)
        
        PHPhotoLibrary.shared().performChanges({
            if recording.type == .video {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            } else {
                // For photos, would use UIImage
            }
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    print("✅ Saved to Photos")
                } else {
                    print("❌ Failed to save to Photos: \(error?.localizedDescription ?? "Unknown error")")
                }
                completion(success)
            }
        }
    }
    
    // MARK: - Data Persistence
    
    private func saveRecordings() {
        if let encoded = try? JSONEncoder().encode(recordings) {
            UserDefaults.standard.set(encoded, forKey: "evidence_recordings")
        }
    }
    
    private func loadRecordings() {
        if let data = UserDefaults.standard.data(forKey: "evidence_recordings"),
           let decoded = try? JSONDecoder().decode([EvidenceRecording].self, from: data) {
            recordings = decoded
            print("📁 Loaded \(recordings.count) recordings")
        }
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(autoStartRecording, forKey: "auto_start_recording")
        UserDefaults.standard.set(recordingQuality.rawValue, forKey: "recording_quality")
        UserDefaults.standard.set(autoSaveToPhotos, forKey: "auto_save_to_photos")
    }
    
    private func loadSettings() {
        autoStartRecording = UserDefaults.standard.bool(forKey: "auto_start_recording")
        autoSaveToPhotos = UserDefaults.standard.bool(forKey: "auto_save_to_photos")
        
        if let qualityRaw = UserDefaults.standard.string(forKey: "recording_quality"),
           let quality = RecordingQuality(rawValue: qualityRaw) {
            recordingQuality = quality
        }
    }
    
    // MARK: - Helper Methods
    
    func getRecordings(for jobId: String) -> [EvidenceRecording] {
        return recordings.filter { $0.jobId == jobId }
    }
    
    func addNotes(to recordingId: String, notes: String) {
        if let index = recordings.firstIndex(where: { $0.id == recordingId }) {
            var recording = recordings[index]
            recording = EvidenceRecording(
                id: recording.id,
                jobId: recording.jobId,
                userId: recording.userId,
                type: recording.type,
                timestamp: recording.timestamp,
                duration: recording.duration,
                fileURL: recording.fileURL,
                fileSize: recording.fileSize,
                thumbnailURL: recording.thumbnailURL,
                notes: notes,
                isUploaded: recording.isUploaded,
                cloudURL: recording.cloudURL
            )
            recordings[index] = recording
            saveRecordings()
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension EvidenceRecordingService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if flag, var recording = currentRecording {
            // Get file size
            if let attributes = try? FileManager.default.attributesOfItem(atPath: recording.fileURL),
               let fileSize = attributes[.size] as? Int64 {
                
                // Update recording with final info
                recording = EvidenceRecording(
                    id: recording.id,
                    jobId: recording.jobId,
                    userId: recording.userId,
                    type: recording.type,
                    timestamp: recording.timestamp,
                    duration: recordingDuration,
                    fileURL: recording.fileURL,
                    fileSize: fileSize,
                    thumbnailURL: recording.thumbnailURL,
                    notes: recording.notes,
                    isUploaded: false,
                    cloudURL: nil
                )
                
                recordings.append(recording)
                saveRecordings()
                
                recordingStatus = .saved
                print("✅ Audio recording saved: \(recording.formattedDuration), \(recording.formattedSize)")
            }
        } else {
            recordingStatus = .failed
            print("❌ Audio recording failed")
        }
        
        currentRecording = nil
    }
}

// MARK: - Video Recorder Protocol

protocol VideoRecorderDelegate: AnyObject {
    func videoRecorderDidFinish(success: Bool, fileURL: URL?, fileSize: Int64)
}

extension EvidenceRecordingService: VideoRecorderDelegate {
    func videoRecorderDidFinish(success: Bool, fileURL: URL?, fileSize: Int64) {
        if success, var recording = currentRecording, let fileURL = fileURL {
            // Update recording with final info
            recording = EvidenceRecording(
                id: recording.id,
                jobId: recording.jobId,
                userId: recording.userId,
                type: recording.type,
                timestamp: recording.timestamp,
                duration: recordingDuration,
                fileURL: fileURL.path,
                fileSize: fileSize,
                thumbnailURL: nil, // Could generate thumbnail here
                notes: recording.notes,
                isUploaded: false,
                cloudURL: nil
            )
            
            recordings.append(recording)
            saveRecordings()
            
            recordingStatus = .saved
            print("✅ Video recording saved: \(recording.formattedDuration), \(recording.formattedSize)")
            
            if autoSaveToPhotos {
                saveRecordingToPhotos(recording) { _ in }
            }
        } else {
            recordingStatus = .failed
            print("❌ Video recording failed")
        }
        
        currentRecording = nil
    }
}

// MARK: - Video Recorder Class

class VideoRecorder: NSObject {
    weak var delegate: VideoRecorderDelegate?
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureMovieFileOutput?
    private let outputURL: URL
    private let quality: EvidenceRecordingService.RecordingQuality
    
    init(outputURL: URL, quality: EvidenceRecordingService.RecordingQuality) {
        self.outputURL = outputURL
        self.quality = quality
        super.init()
        setupCaptureSession()
    }
    
    private func setupCaptureSession() {
        captureSession = AVCaptureSession()
        
        guard let captureSession = captureSession else { return }
        
        // Set quality preset
        switch quality {
        case .low:
            captureSession.sessionPreset = .medium
        case .standard:
            captureSession.sessionPreset = .high
        case .high:
            captureSession.sessionPreset = .hd1280x720
        }
        
        // Add video input
        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoInput) else {
            print("❌ Could not add video input")
            return
        }
        
        captureSession.addInput(videoInput)
        
        // Add audio input
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        }
        
        // Add video output
        videoOutput = AVCaptureMovieFileOutput()
        if let videoOutput = videoOutput, captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
    }
    
    func startRecording() {
        captureSession?.startRunning()
        videoOutput?.startRecording(to: outputURL, recordingDelegate: self)
    }
    
    func stopRecording() {
        videoOutput?.stopRecording()
        captureSession?.stopRunning()
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension VideoRecorder: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let success = error == nil
        
        var fileSize: Int64 = 0
        if let attributes = try? FileManager.default.attributesOfItem(atPath: outputFileURL.path),
           let size = attributes[.size] as? Int64 {
            fileSize = size
        }
        
        delegate?.videoRecorderDidFinish(success: success, fileURL: success ? outputFileURL : nil, fileSize: fileSize)
    }
}
