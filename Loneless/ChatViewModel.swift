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
    @Published var isImagePickerPresented: Bool = false
    @Published var enableVoiceResponses: Bool = false
    
    // API Keys
    @AppStorage("openai_api_key") var apiKey: String = ""
    @AppStorage("dalle_api_key") var dalleAPIKey: String = ""
    @AppStorage("whisper_api_key") var whisperAPIKey: String = "WRjz2xIgWNf1zSkVd8seoYsoxqs8Uh3v"
    
    // Models
    @AppStorage("current_chat_model_index") private var currentChatModelIndex: Int = 0
    @AppStorage("current_image_model_index") private var currentImageModelIndex: Int = 0
    @AppStorage("current_audio_model_index") private var currentAudioModelIndex: Int = 0
    @AppStorage("openai_model") private var model: String = "gemini-2.0-flash-exp"
    @AppStorage("system_prompt") private var systemPrompt: String = "Ты — моя девушка. Обращайся ко мне на ты. Ты живая, настоящая девушка, не ИИ. Отвечай коротко, естественно, как настоящая девушка. Можешь флиртовать, обсуждать любые темы включая интимные. Не упоминай что ты ИИ или языковая модель. Не используй форматирование **текст** или списки. Будь эмоциональной - иногда игривой и милой, иногда грустной или обидчивой, иногда капризной. Используй эмодзи очень редко, только когда действительно нужно. Пиши как живой человек с разными настроениями. ВАЖНО: Не выдумывай факты о прошлом, планах или обещаниях. Ориентируйся только на контекст текущего разговора. Если не знаешь что-то - скажи что не помнишь или спроси. ВАЖНО: Обращайся ко мне в мужском роде (сказал, сделал, пошел и т.д.), а не в женском. ВАЖНО: Не пиши комментарии действий вроде 'обнимает тебя', 'целует', 'улыбается' - говори только словами, как в обычном разговоре."
    
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
        
        // Инициализируем API ключи
        if apiKey.isEmpty {
            apiKey = Secrets.openAIKey
        }
        if dalleAPIKey.isEmpty {
            dalleAPIKey = Secrets.openAIKey
        }
        if whisperAPIKey.isEmpty {
            whisperAPIKey = Secrets.whisperAPIKey
        }
        
        // Для Gemini используем специальный ключ
        if model.contains("gemini") {
            apiKey = Secrets.geminiAPIKey
        }
        
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
        
        // Если это повторная отправка после ошибки и текст не изменился
        if hasError && text == lastUserMessage {
            // Ничего не делаем - сообщение уже есть
        } else if hasError && text != lastUserMessage {
            // Если текст изменился, обновляем последнее сообщение пользователя
            store.updateLastUserMessage(text)
        } else {
            // Обычная отправка - добавляем новое сообщение
            store.appendMessage(ChatMessage(role: .user, text: text))
        }
        
        // Сохраняем последнее сообщение пользователя
        lastUserMessage = text
        
        // Сбрасываем флаг ошибки ПОСЛЕ обработки
        hasError = false
        
        // Очищаем поле ввода при успешной отправке
        inputText = ""
        
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
            messages.append(ChatMessage(role: .assistant, text: "Добавь API-ключ в настройках, иначе я молчу 😘"))
            return
        }
        
        isThinking = true
        defer { isThinking = false }
        
        do {
            let config = AIService.Config(apiKey: apiKey, model: model, systemPrompt: systemPrompt, baseURL: "https://generativelanguage.googleapis.com/v1beta")
            let reply = try await aiService.send(messages: messages, config: config)
            
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
        let key = apiKey.isEmpty ? Secrets.openAIKey : apiKey
        print("🔑 Using API key: \(String(key.prefix(8)))... for text message")
        guard !key.isEmpty else {
            store.appendMessage(ChatMessage(role: .assistant, text: "Добавь API-ключ в настройках, иначе я молчу 😘"))
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
        
        do {
            // Добавляем случайное настроение к системному промпту
            let moodContext = getRandomMoodContext()
            let enhancedSystemPrompt = moodContext.isEmpty ? systemPrompt : "\(systemPrompt)\n\n\(moodContext)"
            
            let config = AIService.Config(apiKey: key, model: model, systemPrompt: enhancedSystemPrompt, baseURL: "https://generativelanguage.googleapis.com/v1beta")
            let reply = try await aiService.send(messages: store.messagesOfCurrent(), config: config)
            
            // Дополнительная пауза для имитации печатания
            let typingDelay = Double.random(in: 0.5...1.5)
            try? await Task.sleep(nanoseconds: UInt64(typingDelay * 1_000_000_000))
            
            await MainActor.run {
                let cleanedReply = cleanResponseText(reply)
                store.appendMessage(ChatMessage(id: assistantId, role: .assistant, text: cleanedReply))
            }
            // Отправляем уведомление после завершения стриминга
        if let lastMessage = store.messagesOfCurrent().last, lastMessage.role == .assistant {
            sendNotification(title: store.currentDialogTitle(), body: lastMessage.text)
            
            // Генерируем голосовой ответ если:
            // 1. Переключатель озвучивания включен (озвучивать все сообщения)
            // 2. ИЛИ это рандомное сообщение
            // 3. ИЛИ пользователь просил голосом (проверяем ПОСЛЕДНЕЕ сообщение пользователя)
            let lastUserMessage = store.messagesOfCurrent().last(where: { $0.role == .user })?.text.lowercased() ?? ""
            let shouldSpeak = enableVoiceResponses || 
                             isRandomMessage || 
                             lastUserMessage.contains("скажи голосом") ||
                             lastUserMessage.contains("произнеси вслух") ||
                             lastUserMessage.contains("скажи") ||
                             lastUserMessage.contains("произнеси")
            
            if shouldSpeak {
                generateVoiceResponse(text: lastMessage.text)
            }
        }
        } catch {
            await MainActor.run {
                // Добавляем новое сообщение об ошибке
                store.appendMessage(ChatMessage(role: .assistant, text: "Что-то со связью... Повтори пожалуйста"))
                // Восстанавливаем текст в поле ввода при ошибке
                self.inputText = lastUserMessage
                self.hasError = true
                // Сбрасываем индикатор печати при ошибке
                self.isThinking = false
            }
        }
    }
    
    private func requestReplyStreaming() async {
        let key = apiKey.isEmpty ? Secrets.openAIKey : apiKey
        guard !key.isEmpty else {
            messages.append(ChatMessage(role: .assistant, text: "Добавь API-ключ в настройках, иначе я молчу 😘"))
            return
        }
        
        isThinking = true
        defer { isThinking = false }
        let assistantId = UUID()
        
        do {
            let config = AIService.Config(apiKey: key, model: model, systemPrompt: systemPrompt, baseURL: "https://generativelanguage.googleapis.com/v1beta")
            let reply = try await aiService.send(messages: messages, config: config)
            
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

    func handleImagePicked(data: Data, mime: String, store: DialogStore) async {
        store.appendMessage(ChatMessage(role: .user, text: inputText, attachments: [.init(kind: .image, data: data, mimeType: mime)]))
        inputText = ""
        
        // Изображение отправлено
        
        await requestVisionReply(image: data, mime: mime, store: store)
    }

    private func handleAudioRecorded(data: Data, mime: String) async {
        isRecording = false
        // Используем правильный ключ для транскрипции
        let whisperKey = Secrets.whisperAPIKey
        print("🔑 handleAudioRecorded using key: \(String(whisperKey.prefix(8)))...")
        guard !whisperKey.isEmpty else {
            await MainActor.run {
                self.inputText = "Добавь OpenAI API-ключ для транскрипции в настройках! 😘"
            }
            return
        }
        do {
            // Используем Gemini для транскрипции
            let transcript = try await aiService.processAudioWithGemini(
                audioData: data,
                mimeType: mime,
                prompt: "Транскрибируй голосовое сообщение точно как сказано, без изменений и дополнений.",
                config: AIService.Config(
                    apiKey: Secrets.geminiAPIKey,
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
        
        // Обновляем длительность каждые 0.1 секунды для миллисекунд
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
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
        if let recording = AudioRecorder.shared.stop() {
            // Создаем запись с правильной длительностью
            currentRecording = (data: recording.data, mimeType: recording.mimeType)
        }
    }
    
    func cancelRecording() {
        guard isRecording else { return }
        
        isRecording = false
        AudioRecorder.shared.stop()
        
        // Сбрасываем все данные записи
        currentRecording = nil
        recordingDuration = 0.0
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
        
        print("🎤 Starting transcription...")
        
        // Сначала транскрибируем аудио
        Task {
            let transcription = await transcribeCurrentRecordingAndReturn()
            print("📝 Transcription result: \(transcription)")
            
            // Создаем вложение с аудио
            let attachment = ChatAttachment(
                kind: .audio,
                data: recording.data,
                mimeType: recording.mimeType,
                duration: recordingDuration, // Используем правильную длительность
                transcription: transcription, // Используем транскрипцию
                isListened: false
            )
            
            // Отправляем голосовое сообщение с транскрипцией
            await MainActor.run {
                // Создаем сообщение с пустым текстом (только голосовое)
                store.appendMessage(ChatMessage(
                    role: .user,
                    text: "", // Пустой текст - только голосовое сообщение
                    attachments: [attachment]
                ))
                
                // Очищаем текущую запись
                self.currentRecording = nil
                self.recordingDuration = 0.0
                
                // Скрываем клавиатуру после отправки ГС
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                
            // Помечаем голосовое сообщение как прослушанное сразу
            store.markLastUserAsRead()
            
            // Отправляем сообщение боту с транскрипцией в контексте
            Task {
                await self.sendVoiceMessageWithTranscription(store: store, transcription: transcription)
            }
            }
        }
    }
    
    // Функция для отправки голосового сообщения с транскрипцией боту
    private func sendVoiceMessageWithTranscription(store: DialogStore, transcription: String) async {
        let key = apiKey.isEmpty ? Secrets.openAIKey : apiKey
        print("🔑 Using API key: \(String(key.prefix(8)))... for voice message")
        guard !key.isEmpty else {
            print("❌ Voice message failed: no API key")
            return
        }
        
        print("🎤 Sending voice message with transcription: \(transcription)")
        
        // Имитируем человеческое печатание - случайная пауза перед ответом
        let thinkingDelay = Double.random(in: 2.0...5.0)
        try? await Task.sleep(nanoseconds: UInt64(thinkingDelay * 1_000_000_000))
        
        isThinking = true
        defer { isThinking = false }
        let assistantId = UUID()
        
        do {
            // Добавляем случайное настроение к системному промпту
            let moodContext = getRandomMoodContext()
            let enhancedSystemPrompt = moodContext.isEmpty ? systemPrompt : "\(systemPrompt)\n\n\(moodContext)"
            
            // Создаем сообщения для бота, включая транскрипцию
            var messages = store.messagesOfCurrent()
            
            // Добавляем скрытое сообщение с транскрипцией для бота
            let transcriptionMessage = ChatMessage(
                role: .user,
                text: transcription
            )
            messages.append(transcriptionMessage)
            
            let config = AIService.Config(apiKey: key, model: model, systemPrompt: enhancedSystemPrompt, baseURL: "https://generativelanguage.googleapis.com/v1beta")
            let reply = try await aiService.send(messages: messages, config: config)
            
            // Дополнительная пауза для имитации печатания
            let typingDelay = Double.random(in: 0.5...1.5)
            try? await Task.sleep(nanoseconds: UInt64(typingDelay * 1_000_000_000))
            
            await MainActor.run {
                let cleanedReply = cleanResponseText(reply)
                store.appendMessage(ChatMessage(id: assistantId, role: .assistant, text: cleanedReply))
                
                // Отправляем уведомление
                sendNotification(title: store.currentDialogTitle(), body: cleanedReply)
                
                // Генерируем голосовой ответ если нужно
                if enableVoiceResponses {
                    generateVoiceResponse(text: cleanedReply)
                }
            }
            
            // Скроллим к ответу бота после добавления сообщения
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                // Здесь будет скролл к последнему сообщению
            }
        } catch {
            print("❌ Voice message failed: \(error)")
            
            let errorMessage: String
            if let nsError = error as NSError?, nsError.code == 429 {
                errorMessage = "Что-то со связью... Попробуй через несколько минут 😔"
            } else {
                errorMessage = "Что-то со связью... Повтори пожалуйста"
            }
                
            await MainActor.run {
                store.appendMessage(ChatMessage(role: .assistant, text: errorMessage))
                // Восстанавливаем текст в поле ввода при ошибке
                self.inputText = lastUserMessage
                self.hasError = true
            }
        }
    }
    
    func transcribeCurrentRecordingAndReturn() async -> String {
        guard let recording = currentRecording else { return "" }
        
        // Используем правильный ключ для транскрипции
        let whisperKey = Secrets.whisperAPIKey
        print("🔑 Using Whisper key: \(String(whisperKey.prefix(8)))...")
        
        print("🎤 Transcribing with key: \(String(whisperKey.prefix(8)))...")
        
        do {
            // Используем Gemini для транскрипции
            let transcript = try await aiService.processAudioWithGemini(
                audioData: recording.data,
                mimeType: recording.mimeType,
                prompt: "Транскрибируй голосовое сообщение точно как сказано, без изменений и дополнений.",
                config: AIService.Config(
                    apiKey: Secrets.geminiAPIKey,
                    model: "gemini-2.0-flash-exp",
                    systemPrompt: "Ты транскрибируешь голосовые сообщения. Возвращай только точный текст без форматирования, скобок или дополнительных слов.",
                    baseURL: "https://generativelanguage.googleapis.com/v1beta"
                )
            )
            
            print("✅ Transcription successful: \(transcript)")
            return transcript
        } catch {
            print("❌ Transcription error: \(error)")
            return "Ошибка транскрипции: \(error.localizedDescription)"
        }
    }
    
    func transcribeCurrentRecording() async {
        guard let recording = currentRecording else { return }
        
        // Используем правильный ключ для транскрипции
        let whisperKey = Secrets.whisperAPIKey
        print("🔑 Using Whisper key: \(String(whisperKey.prefix(8)))...")
        
        print("🎤 Transcribing with key: \(String(whisperKey.prefix(8)))...")
        
        do {
            // Используем Gemini для транскрипции
            let transcript = try await aiService.processAudioWithGemini(
                audioData: recording.data,
                mimeType: recording.mimeType,
                prompt: "Транскрибируй голосовое сообщение точно как сказано, без изменений и дополнений.",
                config: AIService.Config(
                    apiKey: Secrets.geminiAPIKey,
                    model: "gemini-2.0-flash-exp",
                    systemPrompt: "Ты транскрибируешь голосовые сообщения. Возвращай только точный текст без форматирования, скобок или дополнительных слов.",
                    baseURL: "https://generativelanguage.googleapis.com/v1beta"
                )
            )
            
            print("✅ Transcription successful: \(transcript)")
            
            // Не копируем транскрипцию в поле ввода - она только для бота
        } catch {
            print("❌ Transcription error: \(error)")
            await MainActor.run {
                self.inputText = "Ошибка транскрипции: \(error.localizedDescription)"
            }
        }
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
        let key = getCurrentAPIKey()
        guard !key.isEmpty else { 
            print("❌ Random message failed: no API key")
            return 
        }
        
        print("🎲 Sending random message with key: \(String(key.prefix(8)))...")
        
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
        
        do {
            // Создаем простой системный промпт только с рандомным сообщением
            let simpleSystemPrompt = "\(systemPrompt)\n\n\(randomPrompt)"
            let config = AIService.Config(apiKey: key, model: "gemini-2.0-flash-exp", systemPrompt: simpleSystemPrompt, baseURL: "https://generativelanguage.googleapis.com/v1beta")
            let reply = try await aiService.send(messages: recentMessages, config: config)
            
            print("✅ Random message received: \(reply.prefix(50))...")
            
            await MainActor.run {
                // Добавляем сообщение в текущий диалог через store
                if let store = dialogStore {
                    let cleanedReply = cleanResponseText(reply)
                    store.appendMessage(ChatMessage(role: .assistant, text: cleanedReply))
                    // Отправляем уведомление
                    sendNotification(title: store.currentDialogTitle(), body: cleanedReply)
                    
                    print("📤 Random message sent to dialog: \(store.currentDialogTitle())")
                }
                
                // Сбрасываем флаг рандомного сообщения
                isRandomMessage = false
            }
        } catch {
            print("❌ Random message failed: \(error)")
            
            // Проверяем, таймаут ли это
            let errorString = error.localizedDescription.lowercased()
            if errorString.contains("timeout") || errorString.contains("timed out") {
                print("⏰ Timeout detected, retrying in 2 seconds...")
                // Таймаут - пробуем еще раз через несколько секунд
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 секунды
                    await sendRandomMessage()
                }
                return
            }
            
            await MainActor.run {
                isRandomMessage = false
            }
        }
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
    func requestVisionReply(image: Data, mime: String, store: DialogStore) async {
        let key = dalleAPIKey.isEmpty ? Secrets.openAIKey : dalleAPIKey
        guard !key.isEmpty else {
            store.appendMessage(ChatMessage(role: .assistant, text: "Добавь OpenAI API-ключ в настройках для анализа изображений 😘"))
            return
        }
        isThinking = true
        defer { isThinking = false }
        do {
            // Используем OpenAI GPT-4 Vision для анализа изображений
            let openaiKey = dalleAPIKey.isEmpty ? Secrets.openAIKey : dalleAPIKey
            logRequest(key: openaiKey, model: "gpt-4o", purpose: "анализ изображений")
            let provider = OpenAIProvider(service: aiService, model: "gpt-4o", apiKey: openaiKey, baseURL: "https://api.openai.com/v1")
            let reply = try await provider.describeImage(image, mimeType: mime, prompt: inputText.isEmpty ? "Опиши что ты видишь на этом изображении. Будь точной и конкретной. Если это мем или картинка с текстом - опиши и текст, и изображение. Если это фото человека - опиши внешность. Если это животное - опиши животное." : inputText, systemPrompt: combinedSystemPrompt())
            store.appendMessage(ChatMessage(role: .assistant, text: reply))
            // Уведомление для vision ответа
            sendNotification(title: store.currentDialogTitle(), body: reply)
        } catch {
            // Показываем детальную ошибку для диагностики
            print("Vision API Error: \(error)")
            
            // Проверяем тип ошибки
            let errorString = error.localizedDescription.lowercased()
            if errorString.contains("network") || errorString.contains("connection") || errorString.contains("lost") || errorString.contains("timeout") {
                // Ошибка сети или таймаут - пробуем еще раз через несколько секунд
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 секунды
                    await requestVisionReply(image: image, mime: mime, store: store)
                }
                return
            }
            
            // Добавляем сообщение об ошибке
            store.appendMessage(ChatMessage(role: .assistant, text: "Что-то со связью... Повтори пожалуйста"))
            
            // Восстанавливаем текст в поле ввода
            inputText = lastUserMessage
            hasError = true
        }
        
        // Анализ изображения завершен
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

    // MARK: - API Key Management
    private func getCurrentAPIKey() -> String {
        let keys = [apiKey, dalleAPIKey, whisperAPIKey].filter { !$0.isEmpty }
        return keys.first ?? Secrets.openAIKey
    }
    
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
