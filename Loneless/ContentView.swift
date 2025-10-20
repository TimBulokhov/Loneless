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
    @State private var keyboardHeight: CGFloat = 0
    
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
                    .frame(maxHeight: .infinity)
                Divider()
                inputView
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
                    keyboardHeight = keyboardFrame.cgRectValue.height
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardHeight = 0
            }
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
                .onChange(of: dialogStore.messagesOfCurrent().count) { _ in
                    scrollToBottomWithDelay(proxy: proxy, delay: 0.3)
                }
                .onChange(of: viewModel.isThinking) { isThinking in
                    if isThinking {
                        // Скроллим к "Печатает..." когда появляется
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo("thinking", anchor: UnitPoint.bottom)
                            }
                        }
                    }
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
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .listStyle(.plain)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isThinking)
        .onTapGesture {
            // Сбрасываем фокус с поля ввода при тапе по чату
            hideKeyboard()
        }
        .onChange(of: dialogStore.messagesOfCurrent()) { _, _ in
            scrollToBottom(proxy: proxy)
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
            
            HStack(spacing: 8) {
                Text("Печатает")
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
                } else if let recording = viewModel.currentRecording {
                    // HUD голосового сообщения в поле ввода
                    HStack(spacing: 12) {
                        // Кнопка воспроизведения
                        Button(action: {
                            viewModel.playCurrentRecording()
                        }) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.blue)
                        }
                        
                        // Визуализация аудио
                        HStack(spacing: 2) {
                            ForEach(0..<10, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.blue.opacity(0.7))
                                    .frame(width: 2, height: CGFloat.random(in: 4...16))
                            }
                        }
                        .frame(height: 16)
                        
                        Spacer()
                        
                        // Длительность
                        Text(formatDuration(viewModel.recordingDuration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Кнопка удаления (крестик)
                        Button(action: {
                            viewModel.currentRecording = nil
                            viewModel.recordingDuration = 0
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 16))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(16)
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
                        viewModel.isImagePickerPresented = true
                    } label: {
                        Image(systemName: "photo")
                    }
                    .disabled(viewModel.isThinking)
                    
                    Button(action: { 
                        if viewModel.currentRecording != nil {
                            viewModel.sendCurrentRecording(store: dialogStore)
                        } else {
                            viewModel.sendMessage(store: dialogStore)
                        }
                    }) {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled((viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewModel.currentRecording == nil) || viewModel.isThinking)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Recording Interface
    private var recordingInterface: some View {
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
            
            Text("Запись...")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Кнопка отмены записи
            Button(action: {
                viewModel.cancelRecording()
            }) {
                Text("Отмена")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray5))
        .cornerRadius(20)
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let milliseconds = Int((duration.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, milliseconds)
    }
    
    private func formatDurationForSending(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration.rounded()) % 60
        return String(format: "%d:%02d", minutes, seconds)
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
    
    private func scrollToBottomWithDelay(proxy: ScrollViewProxy, delay: Double = 0.5) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
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
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}


#Preview {
    ContentView()
}