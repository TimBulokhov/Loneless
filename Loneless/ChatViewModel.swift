//
//  ChatViewModel.swift
//  Loneless
//
//  Created by Timofey Bulokhov on 16.10.2025.
//

import SwiftUI
import AVFoundation
import os

@MainActor
class ChatViewModel: NSObject, ObservableObject, @preconcurrency AVAudioPlayerDelegate {
    @Published var inputText: String = ""
    @Published var messages: [ChatMessage] = []
    @Published var isThinking: Bool = false
    @Published var hasError: Bool = false
    @Published var lastUserMessage: String = ""
    @Published var isRecording: Bool = false
    @Published var recordingDuration: TimeInterval = 0.0
    @Published var currentRecording: (data: Data, mimeType: String)?
    @Published var currentRecordingDuration: TimeInterval = 0.0
    @Published var savedRecordingDuration: TimeInterval?
    private var recordingTimer: Timer?
    @Published var isImagePickerPresented: Bool = false
    @Published var selectedImage: (data: Data, mimeType: String)?
    @Published var isImageViewerPresented = false
    @Published var selectedImageForViewing: Data?
    @Published var enableVoiceResponses: Bool = false
    
    // API Keys - Only Gemini
    @AppStorage("gemini_api_key") var apiKey: String = ""
    
    // BACKUP: OpenAI settings (commented out for easy restoration)
    // @AppStorage("openai_api_key") var apiKey: String = ""
    // @AppStorage("dalle_api_key") var dalleAPIKey: String = ""
    // @AppStorage("whisper_api_key") var whisperAPIKey: String = "WRjz2xIgWNf1zSkVd8seoYsoxqs8Uh3v"
    
    // Models
    @AppStorage("current_chat_model_index") private var currentChatModelIndex: Int = 0
    @AppStorage("current_image_model_index") private var currentImageModelIndex: Int = 0
    @AppStorage("current_audio_model_index") private var currentAudioModelIndex: Int = 0
    @AppStorage("gemini_model") private var model: String = "gemini-2.0-flash-exp"
    @AppStorage("system_prompt") private var systemPrompt: String = "Ты — моя девушка. Обращайся ко мне на ты. Ты живая, настоящая девушка, не ИИ. Отвечай коротко, естественно, как настоящая девушка. Можешь флиртовать, обсуждать любые темы включая интимные. Не упоминай что ты ИИ или языковая модель. Отвечай СТРОГО ТОЛЬКО на русском языке - НИКОГДА не используй английский. Не используй форматирование **текст** или списки. Будь эмоциональной - иногда игривой и милой, иногда грустной или обидчивой, иногда капризной. Используй эмодзи очень редко, только когда действительно нужно. Пиши как живой человек с разными настроениями. ВАЖНО: Не выдумывай факты о прошлом, планах или обещаниях. Ориентируйся только на контекст текущего разговора. Если не знаешь что-то - скажи что не помнишь или спроси. ВАЖНО: Обращайся ко мне в мужском роде (сказал, сделал, пошел и т.д.), а не в женском. ВАЖНО: Не пиши комментарии действий вроде 'обнимает тебя', 'целует', 'улыбается' - говори только словами, как в обычном разговоре."
    
    // Services
    private var aiService = AIService()
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let logger = Logger(subsystem: "ru.TimBulokhov.Loneless", category: "ChatViewModel")
    
    // Dialog store
    weak var dialogStore: DialogStore?
    
    // API key management
    private var keyUsageStats: Data = Data()
    private var modelUsageStats: Data = Data()
    private var keyLimits: [String: Int] = [:]
    private var modelLimits: [String: Int] = [:]
    private var currentKeyIndex: Int = 0
    private var currentModelIndex: Int = 0
    
    // User profile
    @Published var userProfile: UserProfile = UserProfile()
    @Published var currentDialogAvatar: Data?
    
    // Random messages
    private var isRandomMessage: Bool = false

    init(aiService: AIService = AIService()) {
        self.aiService = aiService
        super.init()
        loadUsageStats()
        loadModelStats()
        
        // Инициализируем Gemini API ключ
        if apiKey.isEmpty {
            apiKey = Secrets.geminiAPIKey
        }
        
        // BACKUP: OpenAI initialization (commented out for easy restoration)
        // if apiKey.isEmpty {
        //     apiKey = Secrets.openAIKey
        // }
        // if dalleAPIKey.isEmpty {
        //     dalleAPIKey = Secrets.openAIKey
        // }
        // if whisperAPIKey.isEmpty {
        //     whisperAPIKey = Secrets.whisperAPIKey
        // }
        // if model.contains("gemini") {
        //     apiKey = Secrets.geminiAPIKey
        // }
        
        // Инициализация завершена
        
        seedGreeting()
        startRandomMessages()
    }

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        
        // Сохраняем последнее сообщение пользователя
        lastUserMessage = text
        inputText = ""

        // messages managed by DialogStore in UI level
        // НЕ вызываем requestReplyStreaming() - это должно происходить через sendMessage(store:)
        print("❌ sendMessage() called without store - this should not happen")
    }

    // New entry point with DialogStore
    func sendMessage(store: DialogStore) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { 
            print("❌ Send message failed: empty text or thinking")
            return 
        }
        
        print("📤 Sending message: \(text)")
        
        // Получаем текущий API ключ
        let key = getCurrentAPIKey()
        
        // Если есть ошибка, удаляем сообщение об ошибке (НЕ заменяем на "Печатает...")
        if hasError {
            store.removeLastErrorMessage()
        }
        
        // Если есть ошибка, заменяем последнее сообщение пользователя
        if hasError {
            store.updateLastUserMessage(text, attachments: []) // Очищаем вложения
        } else {
            // Обычная отправка - добавляем новое сообщение
            store.appendMessage(ChatMessage(role: .user, text: text))
        }
        
        // Сохраняем последнее сообщение пользователя
        lastUserMessage = text
        
        // Сбрасываем флаг ошибки ПОСЛЕ обработки
        hasError = false
        
        // Очищаем ВСЕ поля при отправке
        inputText = ""
        selectedImage = nil
        currentRecording = nil
        recordingDuration = 0.0
        currentRecordingDuration = 0.0
        savedRecordingDuration = nil
        
        // Скрываем клавиатуру после отправки
        DispatchQueue.main.async {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        
        // Запрашиваем обычный текстовый ответ (генерация изображений отключена)
        Task { 
            // Имитируем человеческое печатание - случайная пауза перед ответом (как в ГС)
            let thinkingDelay = Double.random(in: 2.0...5.0)
            try? await Task.sleep(nanoseconds: UInt64(thinkingDelay * 1_000_000_000))
            await requestReplyStreaming(store: store)
        }
        
        // Сообщение отправлено
        
        // сразу помечаем как прочитанное через 1 секунду, имитируя доставку
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            store.markLastUserAsRead()
            store.updateLastSeen()
        }
    }

    private func requestReply() async {
        guard !apiKey.isEmpty else {
            messages.append(ChatMessage(role: .assistant, text: "Добавь Gemini API-ключ в настройках, иначе я молчу 😘"))
            return
        }
        
        isThinking = true
        defer { isThinking = false }
        
        do {
            let config = AIService.Config(apiKey: apiKey, model: model, systemPrompt: systemPrompt, baseURL: "https://generativelanguage.googleapis.com/v1beta")
            let reply = try await self.aiService.send(messages: messages, config: config)
            
            await MainActor.run {
                self.messages.append(ChatMessage(role: .assistant, text: reply))
            }
        } catch {
            await MainActor.run {
                self.messages.append(ChatMessage(role: .assistant, text: "Что-то со связью... Повтори пожалуйста"))
            }
        }
    }

    private func requestReplyStreaming(store: DialogStore) async {
        guard !apiKey.isEmpty || !Secrets.geminiAPIKeys.isEmpty else {
            store.appendMessage(ChatMessage(role: .assistant, text: "Добавь Gemini API-ключ в настройках, иначе я молчу 😘"))
            return
        }
        
        isThinking = true
        defer { isThinking = false }
        let assistantId = UUID()
        
        // Уведомляем UI о том, что нужно скроллить к "Печатает..."
        await MainActor.run {
            // Это вызовет onChange в ContentView
        }
        
        // Дополнительная пауза для имитации печатания
        let typingDelay = Double.random(in: 0.5...1.5)
        try? await Task.sleep(nanoseconds: UInt64(typingDelay * 1_000_000_000))
        
        await executeWithRotation(
            operation: { currentKey, currentModel in
                print("🔑 Using key: \(String(currentKey.prefix(8)))... and model: \(currentModel) for text message")
                
                // Добавляем случайное настроение к системному промпту
                let moodContext = self.getRandomMoodContext()
                let enhancedSystemPrompt = moodContext.isEmpty ? self.systemPrompt : "\(self.systemPrompt)\n\n\(moodContext)"
                
                let config = AIService.Config(apiKey: currentKey, model: currentModel, systemPrompt: enhancedSystemPrompt, baseURL: "https://generativelanguage.googleapis.com/v1beta")
                return try await self.self.aiService.send(messages: store.messagesOfCurrent(), config: config)
            },
            onSuccess: { reply in
                // Дополнительная пауза для имитации печатания
                let typingDelay = Double.random(in: 0.5...1.5)
                try? await Task.sleep(nanoseconds: UInt64(typingDelay * 1_000_000_000))
            
            await MainActor.run {
                    let cleanedReply = self.cleanResponseText(reply)
                    store.appendMessage(ChatMessage(id: assistantId, role: .assistant, text: cleanedReply))
            }
                
            // Отправляем уведомление после завершения стриминга
        if let lastMessage = store.messagesOfCurrent().last, lastMessage.role == .assistant {
                    self.sendNotification(title: store.currentDialogTitle(), body: lastMessage.text)
            
            // Генерируем голосовой ответ если:
            // 1. Переключатель озвучивания включен (озвучивать все сообщения)
            // 2. ИЛИ это рандомное сообщение
            // 3. ИЛИ пользователь просил голосом (проверяем ПОСЛЕДНЕЕ сообщение пользователя)
            let lastUserMessage = store.messagesOfCurrent().last(where: { $0.role == .user })?.text.lowercased() ?? ""
                    let shouldSpeak = self.enableVoiceResponses || 
                                     self.isRandomMessage || 
                             lastUserMessage.contains("скажи голосом") ||
                             lastUserMessage.contains("произнеси вслух") ||
                             lastUserMessage.contains("скажи") ||
                             lastUserMessage.contains("произнеси")
            
            if shouldSpeak {
                        self.generateVoiceResponse(text: lastMessage.text)
            }
        }
            },
            onError: { error in
            await MainActor.run {
                // Добавляем новое сообщение об ошибке
                store.appendMessage(ChatMessage(role: .assistant, text: "Что-то со связью... Повтори пожалуйста"))
                    // Восстанавливаем текст в поле ввода при ошибке
                    self.inputText = self.lastUserMessage
                    self.hasError = true
                    // Сбрасываем индикатор печати при ошибке
                    self.isThinking = false
            }
        }
        )
    }
    
    private func requestReplyStreaming() async {
        let key = apiKey.isEmpty ? Secrets.geminiAPIKey : apiKey
        guard !key.isEmpty else {
            messages.append(ChatMessage(role: .assistant, text: "Добавь Gemini API-ключ в настройках, иначе я молчу 😘"))
            return
        }
        
        isThinking = true
        defer { isThinking = false }
        let assistantId = UUID()
        
        do {
            let config = AIService.Config(apiKey: key, model: model, systemPrompt: systemPrompt, baseURL: "https://generativelanguage.googleapis.com/v1beta")
            let reply = try await self.aiService.send(messages: messages, config: config)
            
            await MainActor.run {
                messages.append(ChatMessage(id: assistantId, role: .assistant, text: reply))
            }
        } catch {
            await MainActor.run {
                messages.append(ChatMessage(role: .assistant, text: "Что-то со связью... Повтори пожалуйста"))
            }
            
            // Восстанавливаем текст в поле ввода
            inputText = lastUserMessage
            hasError = true
        }
    }

    // MARK: - Media
    var onImagePicked: (Data, String) -> Void = { _, _ in }

    func handleImagePicked(data: Data, mime: String) {
        // Заменяем выбранное изображение
        selectedImage = (data: data, mimeType: mime)
    }
    
    func removeSelectedImage() {
        selectedImage = nil
    }
    
    func clearSelectedImage() {
        selectedImage = nil
    }
    
    func viewImage(_ data: Data) {
        selectedImageForViewing = data
        isImageViewerPresented = true
    }
    
    func sendSelectedImage(store: DialogStore) async {
        guard let image = selectedImage else { return }
        
        // Сохраняем данные для возможного восстановления при ошибке
        let imageToSend = image
        let textToSend = inputText
        
        // Если есть ошибка, удаляем сообщение об ошибке
        if hasError {
            store.removeLastErrorMessage()
        }
        
        // Создаем вложение для изображения
        let attachment = ChatAttachment(kind: .image, data: imageToSend.data, mimeType: imageToSend.mimeType)
        
        // Если есть ошибка, заменяем последнее сообщение пользователя
        if hasError {
            store.updateLastUserMessage(textToSend, attachments: [attachment])
        } else {
            // Обычная отправка - добавляем новое сообщение
            store.appendMessage(ChatMessage(role: .user, text: textToSend, attachments: [attachment]))
        }
        
        // Отмечаем как прочитанное
        store.markLastUserAsRead()
        
        // Очищаем поля
        inputText = ""
        selectedImage = nil
        hasError = false
        
        // Скрываем клавиатуру
        DispatchQueue.main.async {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        
        // Отправляем на анализ
        await requestVisionReply(images: [imageToSend], text: textToSend, store: store, isCombinedWithVoice: false)
    }
    
    func sendCurrentRecordingWithImage(store: DialogStore) async {
        guard let recording = currentRecording, let image = selectedImage else { return }
        
        // Проверяем, не идет ли уже обработка
        guard !isThinking else {
            print("⚠️ Already processing, ignoring duplicate request")
            return
        }
        
        print("🎤 Starting transcription with image...")
        
        // Сохраняем данные для восстановления при ошибке
        let savedAudioData = recording.data
        let savedAudioMimeType = recording.mimeType
        let savedImageData = image.data
        let savedImageMimeType = image.mimeType
        let savedText = inputText
        let savedDuration = currentRecordingDuration
        
        // Сначала транскрибируем аудио
        Task {
            do {
                let transcription = await transcribeCurrentRecordingAndReturn()
                print("📝 Transcription result: \(transcription)")
                
                // Создаем вложения для голосового сообщения и изображения
                let audioAttachment = ChatAttachment(
                    kind: .audio,
                    data: recording.data,
                    mimeType: recording.mimeType,
                    duration: self.currentRecordingDuration,
                    transcription: transcription,
                    isListened: false
                )
                
                let imageAttachment = ChatAttachment(
                    kind: .image,
                    data: image.data,
                    mimeType: image.mimeType
                )
                
                // Сохраняем текст для анализа ПЕРЕД очисткой
                let textForAnalysis = self.inputText.isEmpty ? transcription : "\(self.inputText)\n\n\(transcription)"
                
                // Отправляем комбинированное сообщение
                await MainActor.run {
                    // Если есть ошибка, удаляем сообщение об ошибке
                    if self.hasError {
                        store.removeLastErrorMessage()
                    }
                    
                    // Если есть ошибка, заменяем последнее сообщение пользователя
                    if self.hasError {
                        store.updateLastUserMessage(self.inputText, attachments: [audioAttachment, imageAttachment])
                    } else {
                        // Обычная отправка - добавляем новое сообщение
                        store.appendMessage(ChatMessage(
                            role: .user,
                            text: self.inputText,
                            attachments: [audioAttachment, imageAttachment]
                        ))
                    }
                    
                // Очищаем поля ПОСЛЕ сохранения текста для анализа
                self.currentRecording = nil
                self.recordingDuration = 0.0
                self.currentRecordingDuration = 0.0
                self.savedRecordingDuration = savedDuration // Сохраняем для восстановления при ошибке
                self.selectedImage = nil
                self.inputText = ""
                self.hasError = false
                    
                    // Скрываем клавиатуру
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    
                    // Помечаем как прочитанное
                    store.markLastUserAsRead()
                }
                
                // Отправляем на анализ изображения с сохраненными данными аудио
                await self.requestVisionReply(
                    images: [image], 
                    text: textForAnalysis, // Текст для анализа (может содержать транскрипцию)
                    store: store, 
                    isCombinedWithVoice: true,
                    savedAudioData: savedAudioData,
                    savedAudioMimeType: savedAudioMimeType,
                    savedAudioDuration: savedDuration,
                    originalUserText: savedText // Исходный текст пользователя для восстановления
                )
            } catch {
                // Обработка ошибки для комбинированной отправки
                await MainActor.run {
                    // Восстанавливаем голосовое сообщение и изображение при ошибке
                    self.currentRecording = (data: savedAudioData, mimeType: savedAudioMimeType)
                    self.currentRecordingDuration = savedDuration // Восстанавливаем длительность
                    self.savedRecordingDuration = savedDuration // Сохраняем для будущих ошибок
                    self.selectedImage = (data: savedImageData, mimeType: savedImageMimeType)
                    self.inputText = savedText
                    self.hasError = true
                }
            }
        }
    }
    
    // Обработка ошибок для комбинированной отправки
    private func handleCombinedSendError(store: DialogStore, audioData: Data, audioMimeType: String, imageData: Data, imageMimeType: String, text: String, duration: TimeInterval) {
        // Восстанавливаем голосовое сообщение и изображение при ошибке
        currentRecording = (data: audioData, mimeType: audioMimeType)
        currentRecordingDuration = duration // Восстанавливаем длительность
        selectedImage = (data: imageData, mimeType: imageMimeType)
        inputText = text
        hasError = true
    }

    private func handleAudioRecorded(data: Data, mime: String) async {
        isRecording = false
        // Используем Gemini для транскрипции
        let geminiKey = apiKey.isEmpty ? Secrets.geminiAPIKey : apiKey
        print("🔑 handleAudioRecorded using Gemini key: \(String(geminiKey.prefix(8)))...")
        guard !geminiKey.isEmpty else {
            await MainActor.run {
                self.inputText = "Добавь Gemini API-ключ для транскрипции в настройках! 😘"
            }
            return
        }
        do {
            // Используем Gemini для транскрипции
            let transcript = try await self.aiService.processAudioWithGemini(
                audioData: data,
                mimeType: mime,
                prompt: "Транскрибируй голосовое сообщение точно как сказано, без изменений и дополнений.",
                config: AIService.Config(
                    apiKey: geminiKey,
                    model: "gemini-2.0-flash-exp",
                    systemPrompt: "Ты транскрибируешь голосовые сообщения. Возвращай только точный текст без форматирования, скобок или дополнительных слов.",
                    baseURL: "https://generativelanguage.googleapis.com/v1beta"
                )
            )
            // Не копируем транскрипцию в поле ввода - она только для бота
        } catch {
            await MainActor.run {
                self.inputText = "Ошибка транскрипции: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Voice Recording
    func startRecording() {
        guard !isRecording else { return }
        
            isRecording = true
            recordingDuration = 0.0
            
        // Начинаем запись
        do {
            try AudioRecorder.shared.start()
        } catch {
            print("Recording error: \(error)")
            isRecording = false
        }
        
        // Обновляем длительность каждые 0.1 секунды для стабильности
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self, self.isRecording else {
                timer.invalidate()
                return
            }
            self.recordingDuration += 0.1
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        
        // Останавливаем таймер
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Сохраняем длительность записи
        currentRecordingDuration = recordingDuration
        
        if let recording = AudioRecorder.shared.stop() {
            // Создаем запись с правильной длительностью
            currentRecording = (data: recording.data, mimeType: recording.mimeType)
        }
    }
    
    func cancelRecording() {
        guard isRecording else { return }
        
        isRecording = false
        
        // Останавливаем таймер
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        AudioRecorder.shared.stop()
        
        // Сбрасываем все данные записи
        currentRecording = nil
        recordingDuration = 0.0
        currentRecordingDuration = 0.0
        savedRecordingDuration = nil
    }
    
    // MARK: - Audio Playback
    private var audioPlayer: AVAudioPlayer?
    
    func playCurrentRecording() {
        guard let recording = currentRecording else { return }
        
        do {
            audioPlayer = try AVAudioPlayer(data: recording.data)
            audioPlayer?.play()
        } catch {
            print("❌ Playback error: \(error)")
        }
    }
    
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
    
    func sendCurrentRecording(store: DialogStore) {
        guard let recording = currentRecording else { return }
        
        // Проверяем, не идет ли уже обработка
        guard !isThinking else {
            print("⚠️ Already processing, ignoring duplicate request")
            return
        }
        
        // Сохраняем длительность перед отправкой
        savedRecordingDuration = currentRecordingDuration
        
        print("🎤 Starting transcription...")
        print("💾 Saved duration: \(savedRecordingDuration ?? 0.0)")
        
        // Сначала транскрибируем аудио
        Task {
            let transcription = await transcribeCurrentRecordingAndReturn()
            print("📝 Transcription result: \(transcription)")
            
            // Создаем вложение с аудио
            let attachment = ChatAttachment(
                kind: .audio,
                data: recording.data,
                mimeType: recording.mimeType,
                duration: self.currentRecordingDuration, // Используем сохраненную длительность
                transcription: transcription, // Используем транскрипцию
                isListened: false
            )
            
            // Отправляем голосовое сообщение с транскрипцией
            await MainActor.run {
                // Если есть ошибка, удаляем сообщение об ошибке
                if self.hasError {
                    store.removeLastErrorMessage()
                }
                
                // Если есть ошибка, заменяем последнее сообщение пользователя
                if self.hasError {
                    store.updateLastUserMessage("", attachments: [attachment])
                } else {
                    // Обычная отправка - добавляем новое сообщение
                store.appendMessage(ChatMessage(
                    role: .user,
                    text: "", // Пустой текст - только голосовое сообщение
                    attachments: [attachment]
                ))
                }
                
                // Очищаем текущую запись
                self.currentRecording = nil
                self.recordingDuration = 0.0
                self.currentRecordingDuration = 0.0
                // НЕ очищаем savedRecordingDuration - она нужна для восстановления при ошибке
                self.hasError = false
                
                // Скрываем клавиатуру после отправки ГС
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                
            // Помечаем голосовое сообщение как прослушанное сразу
            store.markLastUserAsRead()
            
            // Отправляем сообщение боту с транскрипцией в контексте
                Task {
                await self.sendVoiceMessageWithTranscription(store: store, transcription: transcription, recordingData: recording.data, recordingMimeType: recording.mimeType)
            }
            }
        }
    }
    
    // Функция для отправки голосового сообщения с транскрипцией боту
    private func sendVoiceMessageWithTranscription(store: DialogStore, transcription: String, recordingData: Data? = nil, recordingMimeType: String? = nil) async {
        guard !apiKey.isEmpty || !Secrets.geminiAPIKeys.isEmpty else {
            print("❌ Voice message failed: no API key")
            return
        }
        
        // Используем переданные данные или текущую запись
        let audioData: Data
        let audioMimeType: String
        
        if let recordingData = recordingData, let recordingMimeType = recordingMimeType {
            audioData = recordingData
            audioMimeType = recordingMimeType
        } else if let recording = currentRecording {
            audioData = recording.data
            audioMimeType = recording.mimeType
        } else {
            print("❌ No recording data available")
            return
        }
        
        print("🎤 Sending voice message with transcription: \(transcription)")
        
        // Имитируем человеческое печатание - случайная пауза перед ответом
        let thinkingDelay = Double.random(in: 2.0...5.0)
        try? await Task.sleep(nanoseconds: UInt64(thinkingDelay * 1_000_000_000))
        
        isThinking = true
        defer { isThinking = false }
        let assistantId = UUID()
        
        await executeWithRotation(
            operation: { currentKey, currentModel in
                print("🔑 Using key: \(String(currentKey.prefix(8)))... and model: \(currentModel) for voice message")
                
                // Добавляем случайное настроение к системному промпту
                let moodContext = self.getRandomMoodContext()
                let enhancedSystemPrompt = moodContext.isEmpty ? self.systemPrompt : "\(self.systemPrompt)\n\n\(moodContext)"
                
                // Создаем сообщения для бота, включая транскрипцию
                var messages = store.messagesOfCurrent()
                
                // Добавляем скрытое сообщение с транскрипцией для бота
                let transcriptionMessage = ChatMessage(
                    role: .user,
                    text: transcription
                )
                messages.append(transcriptionMessage)
                
                let config = AIService.Config(apiKey: currentKey, model: currentModel, systemPrompt: enhancedSystemPrompt, baseURL: "https://generativelanguage.googleapis.com/v1beta")
                return try await self.aiService.send(messages: messages, config: config)
            },
            onSuccess: { reply in
                // Дополнительная пауза для имитации печатания
                let typingDelay = Double.random(in: 0.5...1.5)
                try? await Task.sleep(nanoseconds: UInt64(typingDelay * 1_000_000_000))
                
                await MainActor.run {
                    let cleanedReply = self.cleanResponseText(reply)
                    store.appendMessage(ChatMessage(id: assistantId, role: .assistant, text: cleanedReply))
                    
                    // Очищаем сохраненную длительность после успешного ответа
                    self.savedRecordingDuration = nil
                    
                    // Отправляем уведомление
                    self.sendNotification(title: store.currentDialogTitle(), body: cleanedReply)
                    
                    // Генерируем голосовой ответ если нужно
                    if self.enableVoiceResponses {
                        self.generateVoiceResponse(text: cleanedReply)
                    }
                }
                
                // Скроллим к ответу бота после добавления сообщения
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    // Здесь будет скролл к последнему сообщению
                }
            },
            onError: { error in
                print("❌ Voice message failed: \(error)")
                
                let errorMessage: String
                if let nsError = error as NSError?, nsError.code == 429 {
                    errorMessage = "Что-то со связью... Попробуй через несколько минут 😔"
                } else {
                    errorMessage = "Что-то со связью... Повтори пожалуйста"
                }
                
                await MainActor.run {
                    store.appendMessage(ChatMessage(role: .assistant, text: errorMessage))
                    // Восстанавливаем голосовое сообщение при ошибке
                    self.currentRecording = (data: audioData, mimeType: audioMimeType)
                    // Восстанавливаем длительность из сохраненного значения
                    if let savedDuration = self.savedRecordingDuration {
                        self.currentRecordingDuration = savedDuration
                        print("✅ Restored duration: \(savedDuration)")
                    } else {
                        print("⚠️ No saved duration found!")
                    }
                    self.hasError = true
                }
            }
        )
    }
    
    func transcribeCurrentRecordingAndReturn() async -> String {
        guard let recording = currentRecording else { return "" }
        
        guard !apiKey.isEmpty || !Secrets.geminiAPIKeys.isEmpty else {
            return "Добавь Gemini API-ключ для транскрипции в настройках! 😘"
        }
        
        var result: String = ""
        
        await executeWithRotation(
            operation: { currentKey, currentModel in
                print("🔑 Using key: \(String(currentKey.prefix(8)))... and model: \(currentModel) for transcription")
                
                return try await self.aiService.processAudioWithGemini(
                    audioData: recording.data,
                    mimeType: recording.mimeType,
                    prompt: "Транскрибируй голосовое сообщение точно как сказано, без изменений и дополнений.",
                    config: AIService.Config(
                        apiKey: currentKey,
                        model: currentModel,
                        systemPrompt: "Ты транскрибируешь голосовые сообщения. Возвращай только точный текст без форматирования, скобок или дополнительных слов.",
                        baseURL: "https://generativelanguage.googleapis.com/v1beta"
                    )
                )
            },
            onSuccess: { transcript in
                print("✅ Transcription successful: \(transcript)")
                result = transcript
            },
            onError: { error in
                print("❌ Transcription error: \(error)")
                result = "Ошибка транскрипции: \(error.localizedDescription)"
            }
        )
        
        return result
    }
    
    func transcribeCurrentRecording() async {
        guard let recording = currentRecording else { return }
        
        guard !apiKey.isEmpty || !Secrets.geminiAPIKeys.isEmpty else {
            await MainActor.run {
                self.inputText = "Добавь Gemini API-ключ для транскрипции в настройках! 😘"
            }
            return
        }
        
        await executeWithRotation(
            operation: { currentKey, currentModel in
                print("🔑 Using key: \(String(currentKey.prefix(8)))... and model: \(currentModel) for transcription")
                
                return try await self.aiService.processAudioWithGemini(
                    audioData: recording.data,
                    mimeType: recording.mimeType,
                    prompt: "Транскрибируй голосовое сообщение точно как сказано, без изменений и дополнений.",
                    config: AIService.Config(
                        apiKey: currentKey,
                        model: currentModel,
                        systemPrompt: "Ты транскрибируешь голосовые сообщения. Возвращай только точный текст без форматирования, скобок или дополнительных слов.",
                        baseURL: "https://generativelanguage.googleapis.com/v1beta"
                    )
                )
            },
            onSuccess: { transcript in
                print("✅ Transcription successful: \(transcript)")
                // Не копируем транскрипцию в поле ввода - она только для бота
            },
            onError: { error in
                print("❌ Transcription error: \(error)")
            await MainActor.run {
                    self.inputText = "Ошибка транскрипции: \(error.localizedDescription)"
            }
        }
        )
    }

    // MARK: - Voice Response
    private func generateVoiceResponse(text: String) {
        // Останавливаем предыдущее воспроизведение
        speechSynthesizer.stopSpeaking(at: .immediate)
        
        let utterance = AVSpeechUtterance(string: filterEmojisAndEnhance(text))
        utterance.voice = AVSpeechSynthesisVoice(language: "ru-RU")
        utterance.rate = 0.50 // Быстрее для более живого звучания
        utterance.pitchMultiplier = 1.5 // Немного выше тон для более женственного звучания
        utterance.volume = 0.8
        
        // Небольшая задержка для корректного воспроизведения
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.speechSynthesizer.speak(utterance)
        }
    }
    
    private func filterEmojisAndEnhance(_ text: String) -> String {
        var enhancedText = text
        
        // Убираем все смайлики и эмодзи
        enhancedText = enhancedText.replacingOccurrences(of: "[\\p{So}\\p{Cn}]", with: "", options: .regularExpression)
        
        // Убираем "..." как паузы
        enhancedText = enhancedText.replacingOccurrences(of: "...", with: "")
        enhancedText = enhancedText.replacingOccurrences(of: "…", with: "")
        
        // Убираем жирный текст
        enhancedText = enhancedText.replacingOccurrences(of: "\\*\\*", with: "", options: .regularExpression)
        
        // Убираем маркированные списки
        enhancedText = enhancedText.replacingOccurrences(of: "\\* ", with: "", options: .regularExpression)
        enhancedText = enhancedText.replacingOccurrences(of: "- ", with: "", options: .regularExpression)
        
        // Убираем нумерацию списков
        enhancedText = enhancedText.replacingOccurrences(of: "\\d+\\. ", with: "", options: .regularExpression)
        
        // Убираем лишние пробелы и переносы строк
        enhancedText = enhancedText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        // Добавляем эмоциональность - замедляем темп для более живого звучания
        enhancedText = enhancedText.replacingOccurrences(of: "!", with: "! ")
        enhancedText = enhancedText.replacingOccurrences(of: "?", with: "? ")
        
        return enhancedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Функция для фильтрации форматирования в текстовых ответах
    private func cleanResponseText(_ text: String) -> String {
        var cleanedText = text
        
        // Убираем жирный текст
        cleanedText = cleanedText.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "$1", options: .regularExpression)
        
        // Убираем курсив
        cleanedText = cleanedText.replacingOccurrences(of: "\\*([^*]+)\\*", with: "$1", options: .regularExpression)
        
        // Убираем маркированные списки
        cleanedText = cleanedText.replacingOccurrences(of: "^[\\s]*[\\*\\-] ", with: "", options: [.regularExpression])
        
        // Убираем нумерацию списков
        cleanedText = cleanedText.replacingOccurrences(of: "^[\\s]*\\d+\\. ", with: "", options: [.regularExpression])
        
        // Убираем лишние переносы строк
        cleanedText = cleanedText.replacingOccurrences(of: "\\n\\s*\\n", with: "\n", options: .regularExpression)
        
        return cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Функция для добавления случайного контекста настроения
    private func getRandomMoodContext() -> String {
        let moodContexts = [
            "", // Без дополнительного контекста
            "Ты сегодня в хорошем настроении.",
            "Ты немного устала и грустная.",
            "Ты на него обижена и не хочешь показывать это прямо.",
            "Ты игривая и хочешь пофлиртовать.",
            "Ты скучаешь и нуждаешься в его внимании.",
            "Ты ревнуешь но не хочешь это признавать.",
            "Ты капризная и недовольная чем-то.",
            "Ты одинокая и хочешь поговорить.",
            "Ты в романтичном настроении."
        ]
        return moodContexts.randomElement() ?? ""
    }
    
    func startRandomMessages() {
        Task { @MainActor in
            // Ждем 10 минут перед первым рандомным сообщением
            try? await Task.sleep(nanoseconds: UInt64(1 * 60 * 1_000_000_000))
            
            while true {
                // Рандомная пауза 2-5 минут для тестирования (в продакшене можно увеличить до 60-180 минут)
                let delayMinutes = Int.random(in: 60...180)
                try? await Task.sleep(nanoseconds: UInt64(delayMinutes * 60 * 1_000_000_000))
                
                // Проверяем, что диалог активен и есть сообщения
                guard let store = dialogStore, !store.messagesOfCurrent().isEmpty else { 
                    print("❌ Random message skipped: no dialog or messages")
                    continue 
                }
                
                print("🎲 Attempting to send random message...")
                await sendRandomMessage()
            }
        }
    }

    private func sendRandomMessage() async {
        guard !apiKey.isEmpty || !Secrets.geminiAPIKeys.isEmpty else { 
            print("❌ Random message failed: no API key")
            return 
        }
        
        // Устанавливаем флаг рандомного сообщения
        isRandomMessage = true
        
        // Получаем контекст последних сообщений из текущего диалога (только 3 последних)
        let recentMessages = dialogStore?.messagesOfCurrent().suffix(3) ?? []
        print("📝 Recent messages count: \(recentMessages.count)")
        
        let randomPrompts = [
            // Милые и игривые
            "Напиши короткое милое сообщение своему парню. Ты скучаешь и хочешь поговорить. Можешь спросить о делах или пофлиртовать.",
            "Напиши игривое сообщение своему парню. Ты в хорошем настроении и хочешь развлечься. Будь кокетливой и веселой.",
            "Напиши заботливое сообщение своему парню. Спроси как прошел день, прояви интерес к его делам.",
            
            // Грустные и обидчивые
            "Напиши грустное сообщение своему парню. Ты расстроена чем-то, но не говоришь прямо что. Намекни что тебе плохо.",
            "Напиши обидчивое сообщение своему парню. Ты на него обижена, но не хочешь ссориться. Покажи что ты расстроена.",
            "Напиши капризное сообщение своему парню. Ты недовольна чем-то, но не объясняешь что именно. Будь немного токсичной.",
            
            // Скучающие и одинокие
            "Напиши сообщение своему парню о том что тебе скучно. Ты одна дома и не знаешь чем заняться. Попроси его приехать или поговорить.",
            "Напиши сообщение своему парню о том что ты скучаешь. Ты давно его не видела и хочешь встретиться.",
            "Напиши сообщение своему парню о том что ты чувствуешь себя одинокой. Ты нуждаешься в его внимании и заботе.",
            
            // Ревнивые и подозрительные
            "Напиши ревнивое сообщение своему парню. Ты подозреваешь что он что-то скрывает. Будь настойчивой но не агрессивной.",
            "Напиши сообщение своему парню где ты намекаешь что ревнуешь. Ты недовольна что он мало времени уделяет тебе.",
            
            // Сексуальные и флиртующие
            "Напиши флиртующее сообщение своему парню. Намекни на что-то интимное, но не прямо. Будь игривой и соблазнительной.",
            "Напиши сообщение своему парню где ты намекаешь на секс. Будь кокетливой и загадочной.",
            
            // Обычные и повседневные
            "Напиши обычное сообщение своему парню о том что ты делаешь. Поделись чем-то из своей жизни, расскажи о планах.",
            "Напиши сообщение своему парню с вопросом о его планах. Ты хочешь узнать что он будет делать сегодня или завтра.",
            "Напиши сообщение своему парню где ты просишь совета. У тебя есть какая-то проблема и ты хочешь его мнение.",
            
            // Случайные темы
            "Напиши сообщение своему парню о еде. Ты готовишь что-то или хочешь заказать еду. Спроси что он хочет.",
            "Напиши сообщение своему парню о фильме или сериале. Ты что-то смотришь и хочешь поделиться впечатлениями.",
            "Напиши сообщение своему парню о погоде. Поделись своими мыслями о дне или планах на выходные."
        ]
        
        let randomPrompt = randomPrompts.randomElement() ?? randomPrompts[0]
        print("🎯 Using prompt: \(randomPrompt.prefix(50))...")
        
        await executeWithRotation(
            operation: { currentKey, currentModel in
                print("🎲 Using key: \(String(currentKey.prefix(8)))... and model: \(currentModel) for random message")
                
            // Создаем простой системный промпт только с рандомным сообщением
                let simpleSystemPrompt = "\(self.systemPrompt)\n\n\(randomPrompt)"
                let config = AIService.Config(apiKey: currentKey, model: currentModel, systemPrompt: simpleSystemPrompt, baseURL: "https://generativelanguage.googleapis.com/v1beta")
                return try await self.aiService.send(messages: recentMessages, config: config)
            },
            onSuccess: { reply in
                print("✅ Random message received: \(reply.prefix(50))...")
            
            await MainActor.run {
                // Добавляем сообщение в текущий диалог через store
                    if let store = self.dialogStore {
                        let cleanedReply = self.cleanResponseText(reply)
                        store.appendMessage(ChatMessage(role: .assistant, text: cleanedReply))
                    // Отправляем уведомление
                        self.sendNotification(title: store.currentDialogTitle(), body: cleanedReply)
                    
                        print("📤 Random message sent to dialog: \(store.currentDialogTitle())")
                }
                
                // Сбрасываем флаг рандомного сообщения
                    self.isRandomMessage = false
            }
            },
            onError: { error in
                print("❌ Random message failed: \(error)")
            
            // Проверяем, таймаут ли это
            let errorString = error.localizedDescription.lowercased()
            if errorString.contains("timeout") || errorString.contains("timed out") {
                    print("⏰ Timeout detected, retrying in 2 seconds...")
                // Таймаут - пробуем еще раз через несколько секунд
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 секунды
                    await self.sendRandomMessage()
            }
            return
        }
            
            await MainActor.run {
                    self.isRandomMessage = false
            }
        }
        )
    }

    private func combinedSystemPrompt(extra: String? = nil) -> String {
        let factuality = "Всегда проверяй факты на правдоподобие и не выдумывай. Если спрашивают про места/адреса/заведения (кафе, бары, кальянные и т.п.) — сначала уточни город и район. Если нет актуальных данных или ты не уверена, честно скажи об этом и предложи способы проверки (поиск в картах/отзывы). Никогда не придумывай точные адреса; используй формулировки 'может подойти', 'проверь по картам'. Короткие ответы."
        
        let basePrompt = "\(systemPrompt)\n\n\(factuality)"
        
        if let extra = extra {
            return "\(basePrompt)\n\n\(extra)"
        }
        
        return basePrompt
    }

    // MARK: - Vision API
    func requestVisionReply(images: [(data: Data, mimeType: String)], text: String, store: DialogStore, isCombinedWithVoice: Bool = false, savedAudioData: Data? = nil, savedAudioMimeType: String? = nil, savedAudioDuration: TimeInterval? = nil, originalUserText: String? = nil) async {
        guard !apiKey.isEmpty || !Secrets.geminiAPIKeys.isEmpty else {
            store.appendMessage(ChatMessage(role: .assistant, text: "Добавь Gemini API-ключ в настройках для анализа изображений 😘"))
            return
        }
        
        isThinking = true
        defer { isThinking = false }
        let assistantId = UUID()
        
        // Уведомляем UI о том, что нужно скроллить к "Печатает..."
        await MainActor.run {
            // Это вызовет onChange в ContentView
        }
        
        // Имитируем человеческое печатание - случайная пауза перед ответом
        let thinkingDelay = Double.random(in: 2.0...5.0)
        try? await Task.sleep(nanoseconds: UInt64(thinkingDelay * 1_000_000_000))
        
        await executeWithRotation(
            operation: { currentKey, currentModel in
                print("🔑 Using key: \(String(currentKey.prefix(8)))... and model: \(currentModel) for image analysis")
                
                // Добавляем случайное настроение к системному промпту
                let moodContext = self.getRandomMoodContext()
                let enhancedSystemPrompt = moodContext.isEmpty ? self.systemPrompt : "\(self.systemPrompt)\n\n\(moodContext)"
                
                // Улучшенный промпт для более естественных реакций
                let prompt = text.isEmpty ? 
                    "Посмотри на эти изображения и отреагируй как настоящая девушка. Не описывай подробно что видишь - просто отреагируй естественно, как будто ты смотришь на фото в соцсетях. Если это еда - скажи что думаешь о ней. Если это мем - посмейся или прокомментируй. Если это фото - отреагируй как на обычное фото. Будь живой и естественной!" : 
                    text
                
                let config = AIService.Config(apiKey: currentKey, model: currentModel, systemPrompt: enhancedSystemPrompt, baseURL: "https://generativelanguage.googleapis.com/v1beta")
                
                // Обрабатываем все изображения
                guard !images.isEmpty else {
                    throw NSError(domain: "ImageError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No images to process"])
                }
                
                // Пока что обрабатываем только первое изображение
                // TODO: Добавить поддержку нескольких изображений в AIService
                let firstImage = images.first!
                
                return try await self.aiService.processImageWithGemini(
                    imageData: firstImage.data,
                    mimeType: firstImage.mimeType,
                    prompt: prompt,
                    config: config
                )
            },
            onSuccess: { reply in
                // Дополнительная пауза для имитации печатания
                let typingDelay = Double.random(in: 0.5...1.5)
                try? await Task.sleep(nanoseconds: UInt64(typingDelay * 1_000_000_000))
                
                await MainActor.run {
                    let cleanedReply = self.cleanResponseText(reply)
                    store.appendMessage(ChatMessage(id: assistantId, role: .assistant, text: cleanedReply))
                    
                    // Генерируем голосовой ответ если включено
                    if self.enableVoiceResponses {
                        self.generateVoiceResponse(text: cleanedReply)
                    }
                }
                
                // Уведомление для vision ответа
                self.sendNotification(title: store.currentDialogTitle(), body: reply)
            },
            onError: { error in
                print("❌ Vision analysis failed: \(error)")
                
                let errorMessage: String
                if let nsError = error as NSError?, nsError.code == 429 {
                    errorMessage = "Все ключи исчерпаны... Попробуй завтра или добавь новые ключи 😔"
                } else {
                    errorMessage = "Что-то со связью... Повтори пожалуйста"
                }
                
                await MainActor.run {
                    store.appendMessage(ChatMessage(role: .assistant, text: errorMessage))
                    
                    // Восстанавливаем ВСЕ поля как они были при отправке
                    
                    // Восстанавливаем изображение
                    if let firstImage = images.first {
                        self.selectedImage = firstImage
                    }
                    
                    // Восстанавливаем текст - используем исходный текст пользователя, а не текст для анализа
                    if let originalText = originalUserText {
                        self.inputText = originalText
                    } else {
                        self.inputText = text
                    }
                    
                    // Если это комбинированная отправка с голосом, восстанавливаем ГС
                    if isCombinedWithVoice, 
                       let audioData = savedAudioData, 
                       let audioMimeType = savedAudioMimeType,
                       let audioDuration = savedAudioDuration {
                        self.currentRecording = (data: audioData, mimeType: audioMimeType)
                        self.currentRecordingDuration = audioDuration
                        self.savedRecordingDuration = audioDuration
                    } else if !isCombinedWithVoice {
                        // Если есть сохраненная длительность ГС, восстанавливаем её
                        if let savedDuration = self.savedRecordingDuration {
                            self.currentRecordingDuration = savedDuration
                        }
                    }
                    
                    self.hasError = true
                }
            }
        )
    }

    private func seedGreeting() {
        guard messages.isEmpty else { return }
        messages = [
            ChatMessage(role: .assistant, text: "Привет! Я тут, чтобы составить тебе компанию 💕 Как прошёл твой день?")
        ]
    }

    // MARK: - Notifications
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "MESSAGE_CATEGORY"
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send notification: \(error)")
            } else {
                print("✅ Notification sent: \(title)")
            }
        }
    }

    // MARK: - Voice Toggle
    func toggleVoiceResponses() {
        enableVoiceResponses.toggle()
    }

    // MARK: - Testing Functions
    func sendTestRandomMessage() {
        Task {
            await sendRandomMessage()
        }
    }

    // MARK: - API Key & Model Management
    private var failedKeys: Set<String> = []
    private var failedModels: Set<String> = []
    
    private func getCurrentAPIKey() -> String {
        // If user has set a custom key, use it
        if !apiKey.isEmpty {
            return apiKey
        }
        
        // Try to find a working key from rotation
        let availableKeys = Secrets.geminiAPIKeys.filter { !failedKeys.contains($0) }
        
        if availableKeys.isEmpty {
            // All keys failed, reset and try again
            failedKeys.removeAll()
            return Secrets.geminiAPIKeys.first ?? Secrets.geminiAPIKey
        }
        
        // Use current key or cycle through available keys
        let key = availableKeys[currentKeyIndex % availableKeys.count]
        return key
    }
    
    private func markKeyAsFailed(_ key: String) {
        failedKeys.insert(key)
        print("❌ Key \(String(key.prefix(8)))... marked as failed")
        
        // If all keys failed, reset after some time
        if failedKeys.count >= Secrets.geminiAPIKeys.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 300) { // 5 minutes
                self.failedKeys.removeAll()
                print("🔄 Reset failed keys, trying again...")
            }
        }
    }
    
    private func rotateToNextKey() {
        currentKeyIndex = (currentKeyIndex + 1) % Secrets.geminiAPIKeys.count
        print("🔄 Rotated to key index: \(currentKeyIndex)")
    }
    
    private func getCurrentModel() -> String {
        // Try to find a working model from rotation
        let availableModels = Secrets.supportedModels.filter { !failedModels.contains($0) }
        
        if availableModels.isEmpty {
            // All models failed, reset and try again
            failedModels.removeAll()
            return Secrets.supportedModels.first ?? "gemini-2.0-flash"
        }
        
        // Use current model or cycle through available models
        let model = availableModels[currentModelIndex % availableModels.count]
        return model
    }
    
    private func markModelAsFailed(_ model: String) {
        failedModels.insert(model)
        print("❌ Model \(model) marked as failed")
        
        // If all models failed, reset after some time
        if failedModels.count >= Secrets.supportedModels.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 300) { // 5 minutes
                self.failedModels.removeAll()
                print("🔄 Reset failed models, trying again...")
            }
        }
    }
    
    private func rotateToNextModel() {
        currentModelIndex = (currentModelIndex + 1) % Secrets.supportedModels.count
        print("🔄 Rotated to model index: \(currentModelIndex)")
    }
    
    // Universal function to handle API calls with key and model rotation
    private func executeWithRotation<T>(
        operation: @escaping (String, String) async throws -> T,
        onSuccess: @escaping (T) async -> Void,
        onError: @escaping (Error) async -> Void
    ) async {
        let currentKey = getCurrentAPIKey()
        let currentModel = getCurrentModel()
        
        do {
            let result = try await operation(currentKey, currentModel)
            await onSuccess(result)
        } catch {
            if let nsError = error as NSError?, nsError.code == 429 {
                print("🔄 Quota exceeded for key \(String(currentKey.prefix(8)))... and model \(currentModel), trying next combination...")
                
                // Try next model first
                markModelAsFailed(currentModel)
                rotateToNextModel()
                
                do {
                    let nextModel = getCurrentModel()
                    print("🔄 Retrying with model: \(nextModel)")
                    let result = try await operation(currentKey, nextModel)
                    await onSuccess(result)
                    return
                } catch {
                    // If model rotation failed, try next key
                    print("🔄 Model rotation failed, trying next key...")
                    markKeyAsFailed(currentKey)
                    rotateToNextKey()
                    
                    do {
                        let nextKey = getCurrentAPIKey()
                        let nextModel = getCurrentModel()
                        print("🔄 Retrying with key: \(String(nextKey.prefix(8)))... and model: \(nextModel)")
                        let result = try await operation(nextKey, nextModel)
                        await onSuccess(result)
                        return
                    } catch {
                        print("❌ All retries failed: \(error)")
                        await onError(error)
                    }
                }
            } else {
                await onError(error)
            }
        }
    }
    
    // BACKUP: OpenAI key management (commented out for easy restoration)
    // private func getCurrentAPIKey() -> String {
    //     let keys = [apiKey, dalleAPIKey, whisperAPIKey].filter { !$0.isEmpty }
    //     return keys.first ?? Secrets.openAIKey
    // }
    
    private func logRequest(key: String, model: String, purpose: String) {
        let maskedKey = String(key.prefix(8)) + "..."
        print("🔑 ключ: \(maskedKey) 🤖 модель: \(model) 🎯 назначение: \(purpose)")
    }
    
    private func loadUsageStats() {
        // Загружаем статистику использования ключей
        if let data = UserDefaults.standard.data(forKey: "key_usage_stats"),
           let stats = try? JSONDecoder().decode([String: Int].self, from: data) {
            keyUsageStats = data
        }
        
        // Загружаем статистику использования моделей
        if let data = UserDefaults.standard.data(forKey: "model_usage_stats"),
           let stats = try? JSONDecoder().decode([String: Int].self, from: data) {
            modelUsageStats = data
        }
    }
    
    private func loadModelStats() {
        // Загружаем лимиты ключей
        if let data = UserDefaults.standard.data(forKey: "key_limits"),
           let limits = try? JSONDecoder().decode([String: Int].self, from: data) {
            keyLimits = limits
        }
        
        // Загружаем лимиты моделей
        if let data = UserDefaults.standard.data(forKey: "model_limits"),
           let limits = try? JSONDecoder().decode([String: Int].self, from: data) {
            modelLimits = limits
        }
    }
    
    deinit {
        // Очистка ресурсов
    }
}
