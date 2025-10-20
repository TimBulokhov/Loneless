//
//  AudioRecorder.swift
//  Loneless
//
//  Created by Assistant on 16.10.2025.
//

import Foundation
import AVFoundation

final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = AudioRecorder()
    @Published var isRecording: Bool = false
    private var recorder: AVAudioRecorder?
    
    private override init() {
        super.init()
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice.m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.delegate = self
        recorder?.record()
        DispatchQueue.main.async { self.isRecording = true }
    }

    func stop() -> (data: Data, mimeType: String)? {
        recorder?.stop()
        let url = recorder?.url
        recorder = nil
        DispatchQueue.main.async { self.isRecording = false }
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return (data, "audio/m4a")
    }
}


