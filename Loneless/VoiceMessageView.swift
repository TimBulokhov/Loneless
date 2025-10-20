//
//  VoiceMessageView.swift
//  Loneless
//
//  Created by Assistant on 16.10.2025.
//

import SwiftUI
import AVFoundation

struct VoiceMessageView: View {
    let attachment: ChatAttachment
    let isUserMessage: Bool
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var showTranscription = false
    
    var body: some View {
        VStack(alignment: isUserMessage ? .trailing : .leading, spacing: 8) {
            // Основной интерфейс голосового сообщения
            HStack(spacing: 12) {
                if isUserMessage {
                    // Для пользовательских сообщений - компактно справа
                    Spacer()
                    
                    // Кнопка транскрипции (отдельно, чтобы не пересекалась с play)
                    if let transcription = attachment.transcription, !transcription.isEmpty {
                        Button(action: { 
                            showTranscription.toggle()
                            // НЕ воспроизводим аудио при нажатии на транскрипцию
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "text.bubble")
                                    .font(.system(size: 14))
                                Text("Текст")
                                    .font(.caption)
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle()) // Убираем стандартное поведение кнопки
                    }
                    
                    // Длительность
                    Text(formatDuration(attachment.duration ?? 0))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Визуализация аудио (компактная)
                    HStack(spacing: 3) {
                        ForEach(0..<15, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.blue.opacity(0.7))
                                .frame(width: 3, height: CGFloat.random(in: 6...20))
                                .animation(.easeInOut(duration: 0.3).delay(Double(index) * 0.1), value: isPlaying)
                        }
                    }
                    .frame(height: 20)
                    
                    // Кнопка воспроизведения
                    Button(action: togglePlayback) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle()) // Убираем стандартное поведение кнопки
                    .onTapGesture {
                        togglePlayback()
                    }
                } else {
                    // Для сообщений ассистента - обычный порядок
                    // Кнопка воспроизведения
                    Button(action: togglePlayback) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.blue)
                    }
                    
                    // Визуализация аудио (упрощенная)
                    HStack(spacing: 3) {
                        ForEach(0..<25, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color.blue.opacity(0.7))
                                .frame(width: 4, height: CGFloat.random(in: 6...24))
                                .animation(.easeInOut(duration: 0.3).delay(Double(index) * 0.1), value: isPlaying)
                        }
                    }
                    .frame(height: 24)
                    
                    Spacer()
                    
                    // Длительность
                    Text(formatDuration(attachment.duration ?? 0))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Кнопка транскрипции
                    if let transcription = attachment.transcription, !transcription.isEmpty {
                        Button(action: { 
                            showTranscription.toggle()
                            // НЕ воспроизводим аудио при нажатии на транскрипцию
                        }) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 16))
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            
            // Транскрипция (если есть)
            if showTranscription, let transcription = attachment.transcription {
                Text(transcription)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .padding(.top, 4)
            }
        }
        .onAppear {
            setupAudioPlayer()
        }
        .onDisappear {
            audioPlayer?.stop()
        }
    }
    
    private func setupAudioPlayer() {
        do {
            audioPlayer = try AVAudioPlayer(data: attachment.data)
            audioPlayer?.delegate = AudioPlayerDelegate { [self] in
                isPlaying = false
                currentTime = 0
            }
        } catch {
            print("Failed to setup audio player: \(error)")
        }
    }
    
    private func togglePlayback() {
        guard let player = audioPlayer else { return }
        
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// Делегат для AVAudioPlayer
class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: () -> Void
    
    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

// Предварительный просмотр записи (до отправки)
struct VoiceRecordingPreview: View {
    let recording: VoiceRecording
    let onSend: () -> Void
    let onCancel: () -> Void
    let onPlay: () -> Void
    let onStop: () -> Void
    let isPlaying: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            // Заголовок
            Text("Голосовое сообщение")
                .font(.headline)
            
            // Интерфейс записи
            HStack(spacing: 16) {
                // Кнопка воспроизведения
                Button(action: isPlaying ? onStop : onPlay) {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    // Длительность
                    Text(formatDuration(recording.duration))
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    // Транскрипция (если есть)
                    if let transcription = recording.transcription {
                        Text(transcription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    } else {
                        Text("Транскрибируется...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            
            // Кнопки действий
            HStack(spacing: 16) {
                Button("Отмена", action: onCancel)
                    .foregroundColor(.red)
                
                Spacer()
                
                Button("Отправить", action: onSend)
                    .foregroundColor(.blue)
                    .fontWeight(.medium)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    VStack {
        VoiceMessageView(attachment: ChatAttachment(
            kind: .audio,
            data: Data(),
            mimeType: "audio/m4a",
            duration: 15.5,
            transcription: "Привет, как дела?",
            isListened: false
        ), isUserMessage: false)
        
        VoiceRecordingPreview(
            recording: VoiceRecording(data: Data(), duration: 8.3, transcription: "Тестовое сообщение"),
            onSend: {},
            onCancel: {},
            onPlay: {},
            onStop: {},
            isPlaying: false
        )
    }
    .padding()
}
