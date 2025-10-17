//
//  ContentView.swift
//  Loneless
//
//  Created by Timofey Bulokhov on 16.10.2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject var dialogStore = DialogStore()
    @StateObject private var viewModel = ChatViewModel()
    
    init() {
        let store = DialogStore()
        let vm = ChatViewModel()
        vm.dialogStore = store
        _dialogStore = StateObject(wrappedValue: store)
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                chatMessagesView
                Divider()
                inputView
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NavigationLink { EditDialogView(store: dialogStore) } label: {
                        VStack(spacing: 2) {
                            Text(dialogStore.currentDialogTitle()).font(.headline)
                            Text(dialogStore.lastSeenText()).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { DialogsView(store: dialogStore) } label: { 
                        Image(systemName: "text.bubble") 
                    }
                }
            }
            .sheet(isPresented: $viewModel.isImagePickerPresented) {
                ImagePicker { data, mime in
                    if let data { 
                        Task { await viewModel.handleImagePicked(data: data, mime: mime, store: dialogStore) } 
                    }
                }
            }
            .onAppear {
                viewModel.dialogStore = dialogStore
                viewModel.startRandomMessages()
                updateCurrentDialogAvatar()
            }
        }
    }
    
    // MARK: - Chat Messages View
    private var chatMessagesView: some View {
        ScrollViewReader { proxy in
            messagesList(proxy: proxy)
                .onAppear {
                    scrollToBottom(proxy: proxy)
                }
        }
    }
    
    private func messagesList(proxy: ScrollViewProxy) -> some View {
        List {
            ForEach(groupedMessages(), id: \.date) { section in
                Section(header: DateHeaderView(date: section.date)) {
                    ForEach(section.items) { message in
                        MessageRowView(message: message)
                    }
                }
            }
            if viewModel.isThinking {
                thinkingIndicatorView
            }
        }
        .listStyle(.plain)
        .onChange(of: dialogStore.messagesOfCurrent()) { _, _ in
            scrollToBottom(proxy: proxy)
        }
        .onChange(of: viewModel.isThinking) { _, _ in
            if viewModel.isThinking {
                scrollToBottom(proxy: proxy)
            }
        }
        .onChange(of: dialogStore.currentDialogId) { _, _ in
            updateCurrentDialogAvatar()
        }
    }
    
    // MARK: - Thinking Indicator
    private var thinkingIndicatorView: some View {
        HStack {
            // Аватарка собеседника
            if let dialog = dialogStore.currentDialog(), let avatarData = dialog.avatarData,
               let uiImage = UIImage(data: avatarData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
            } else {
                Image(systemName: "heart.circle.fill")
                    .foregroundStyle(.pink)
                    .font(.system(size: 28))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Печатает...")
                    .padding(10)
                    .background(Color.pink.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                TypingIndicatorView()
            }
        }
        .id("thinking")
    }
    
    // MARK: - Input View
    private var inputView: some View {
        VStack(spacing: 0) {
            // Предварительный просмотр записи
            if let recording = viewModel.currentRecording {
                VoiceRecordingPreview(
                    recording: recording,
                    onSend: { viewModel.sendCurrentRecording(store: dialogStore) },
                    onCancel: { viewModel.cancelRecording() },
                    onPlay: { viewModel.playCurrentRecording() },
                    onStop: { viewModel.stopPlayingRecording() },
                    isPlaying: viewModel.isPlayingRecording
                )
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            
            // Основной интерфейс ввода
            HStack {
                // Переключатель озвучивания
                Button {
                    viewModel.toggleVoiceResponses()
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundColor(viewModel.enableVoiceResponses ? .green : .gray)
                        .font(.system(size: 20))
                }
                .disabled(viewModel.isThinking)
                
                // Поле ввода или интерфейс записи
                if viewModel.isRecording {
                    recordingInterface
                } else {
                    TextField("Сообщение...", text: $viewModel.inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...6)
                        .disabled(viewModel.isThinking)
                }
                
                // Кнопка записи
                Button {
                    if viewModel.isRecording {
                        viewModel.stopRecording()
                    } else {
                        viewModel.startRecording()
                    }
                } label: {
                    Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .foregroundColor(viewModel.isRecording ? .red : .blue)
                        .font(.system(size: 32))
                }
                .disabled(viewModel.isThinking)
                
                // Кнопки действий
                if !viewModel.isRecording {
                    Button {
                        viewModel.pickImage()
                    } label: {
                        Image(systemName: "photo")
                    }
                    .disabled(viewModel.isThinking)
                    
                    Button(action: { viewModel.sendMessage(store: dialogStore) }) {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isThinking)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Recording Interface
    private var recordingInterface: some View {
        HStack {
            // Индикатор записи
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .scaleEffect(viewModel.isRecording ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(), value: viewModel.isRecording)
                
                Text(formatDuration(viewModel.recordingDuration))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("Slide to cancel")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemGray5))
            .cornerRadius(20)
        }
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let milliseconds = Int((duration.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d,%02d", minutes, seconds, milliseconds)
    }
    
    // MARK: - Helper Functions
    private func scrollToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let lastId = dialogStore.messagesOfCurrent().last?.id
            if let lastId {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(lastId, anchor: UnitPoint.bottom)
                }
            } else if viewModel.isThinking {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("thinking", anchor: UnitPoint.bottom)
                }
            }
        }
    }
    
    private func updateCurrentDialogAvatar() {
        if let data = dialogStore.currentDialog()?.avatarData {
            UserDefaults.standard.set(data, forKey: "current_dialog_avatar")
        } else {
            UserDefaults.standard.removeObject(forKey: "current_dialog_avatar")
        }
    }
}

#Preview {
    ContentView()
}