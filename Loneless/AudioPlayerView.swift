//
//  AudioPlayerView.swift
//  Loneless
//
//  Created by Assistant on 16.10.2025.
//

import SwiftUI
import AVFoundation

struct AudioPlayerView: View {
    let data: Data
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false

    var body: some View {
        HStack {
            Button {
                if isPlaying { stop() } else { play() }
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
            }
            Text(isPlaying ? "Воспроизведение..." : "Аудио сообщение")
                .font(.subheadline)
        }
        .onDisappear { stop() }
    }

    private func play() {
        do {
            player = try AVAudioPlayer(data: data)
            player?.play()
            isPlaying = true
        } catch { }
    }

    private func stop() {
        player?.stop()
        isPlaying = false
    }
}


