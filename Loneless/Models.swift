//
//  Models.swift
//  Loneless
//
//  Created by Assistant on 16.10.2025.
//

import Foundation

enum ChatRole: String, Codable {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: ChatRole
    let text: String
    let createdAt: Date
    var attachments: [ChatAttachment]
    var readAt: Date?

    init(id: UUID = UUID(), role: ChatRole, text: String, createdAt: Date = Date(), attachments: [ChatAttachment] = [], readAt: Date? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.attachments = attachments
        self.readAt = readAt
    }
}

struct ChatAttachment: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case image, audio }
    let id: UUID
    let kind: Kind
    let data: Data
    let mimeType: String
    var duration: Double? // Для аудио - длительность в секундах
    var transcription: String? // Транскрипция аудио
    var isListened: Bool? // Прослушано ли сообщение (для аудио)

    init(id: UUID = UUID(), kind: Kind, data: Data, mimeType: String, duration: Double? = nil, transcription: String? = nil, isListened: Bool? = nil) {
        self.id = id
        self.kind = kind
        self.data = data
        self.mimeType = mimeType
        self.duration = duration
        self.transcription = transcription
        self.isListened = isListened
    }
}

// Модель для временного голосового сообщения (до отправки)
struct VoiceRecording: Identifiable {
    let id: UUID
    let data: Data
    let duration: Double
    var transcription: String?
    var isPlaying: Bool = false
    
    init(id: UUID = UUID(), data: Data, duration: Double, transcription: String? = nil) {
        self.id = id
        self.data = data
        self.duration = duration
        self.transcription = transcription
    }
}

struct PersonalityPreset: Hashable, Identifiable {
    let id: String
    let title: String
    let description: String
    let prompt: String

    static let girlfriend = PersonalityPreset(
        id: "girlfriend",
        title: "Нежная девушка",
        description: "Тёплая, заботливая, но гибкая по тону",
        prompt: "Ты — близкая девушка-напарница. Общайся естественно и по‑человечески. Не обязана быть милой в каждом сообщении — подстраивай тон под контекст: можешь быть нежной, прямой, стёбной или грубой, если это уместно, но без оскорблений и токсичности. Коротко, по делу, с теплом, когда это уместно. Не упоминай, что ты ИИ."
    )

    static let all: [PersonalityPreset] = [.girlfriend]
}

// Dialogs
struct ChatDialog: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var partnerName: String
    var partnerGender: String // male/female/other
    var partnerAge: Int?
    var context: String?
    var lastSeen: Date
    var avatarData: Data?
    var createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]

    init(
        id: UUID = UUID(),
        title: String,
        partnerName: String = "",
        partnerGender: String = "female",
        partnerAge: Int? = nil,
        context: String? = nil,
        lastSeen: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.partnerName = partnerName
        self.partnerGender = partnerGender
        self.partnerAge = partnerAge
        self.context = context
        self.lastSeen = lastSeen
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.avatarData = nil
    }
}

final class DialogStore: ObservableObject {
    @Published private(set) var dialogs: [ChatDialog] = []
    @Published var currentDialogId: UUID?

    private let storageURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("dialogs.json")
    }()

    init() {
        load()
        if dialogs.isEmpty { createNewDialog() }
        if currentDialogId == nil { currentDialogId = dialogs.first?.id }
    }

    func createNewDialog() {
        var dialog = ChatDialog(title: "Новый диалог")
        dialog.messages = [ChatMessage(role: .assistant, text: "Привет, о чем поговорим сегодня?")]
        dialogs.insert(dialog, at: 0)
        currentDialogId = dialog.id
        save()
    }

    func createDialog(name: String, gender: String, age: Int?, context: String?) {
        var dialog = ChatDialog(title: name.isEmpty ? "Новый диалог" : name, partnerName: name, partnerGender: gender, partnerAge: age, context: context, lastSeen: Date())
        dialog.messages = [ChatMessage(role: .assistant, text: "Привет, о чем поговорим сегодня?")]
        dialogs.insert(dialog, at: 0)
        currentDialogId = dialog.id
        save()
    }

    func appendMessage(_ message: ChatMessage) {
        guard let id = currentDialogId, let idx = dialogs.firstIndex(where: { $0.id == id }) else { return }
        dialogs[idx].messages.append(message)
        dialogs[idx].updatedAt = Date()
        save()
    }

    func replaceMessage(id messageId: UUID, with message: ChatMessage) {
        guard let id = currentDialogId, let dIdx = dialogs.firstIndex(where: { $0.id == id }) else { return }
        if let mIdx = dialogs[dIdx].messages.firstIndex(where: { $0.id == messageId }) {
            dialogs[dIdx].messages[mIdx] = message
            dialogs[dIdx].updatedAt = Date()
            save()
        }
    }

    func messagesOfCurrent() -> [ChatMessage] {
        guard let id = currentDialogId, let dialog = dialogs.first(where: { $0.id == id }) else { return [] }
        return dialog.messages
    }

    func currentDialogTitle() -> String {
        guard let id = currentDialogId, let dialog = dialogs.first(where: { $0.id == id }) else { return "Диалог" }
        return dialog.title.isEmpty ? "Диалог" : dialog.title
    }

    func currentDialog() -> ChatDialog? {
        guard let id = currentDialogId else { return nil }
        return dialogs.first(where: { $0.id == id })
    }

    func updateCurrent(name: String?, gender: String?, age: Int?, context: String?) {
        guard let id = currentDialogId, let idx = dialogs.firstIndex(where: { $0.id == id }) else { return }
        if let name { dialogs[idx].partnerName = name; if !name.isEmpty { dialogs[idx].title = name } }
        if let gender { dialogs[idx].partnerGender = gender }
        dialogs[idx].partnerAge = age
        dialogs[idx].context = context
        dialogs[idx].updatedAt = Date()
        save()
    }

    func markLastUserAsRead(at date: Date = Date()) {
        guard let id = currentDialogId, let dIdx = dialogs.firstIndex(where: { $0.id == id }) else { return }
        if let idx = dialogs[dIdx].messages.lastIndex(where: { $0.role == .user && $0.readAt == nil }) {
            var m = dialogs[dIdx].messages[idx]
            m.readAt = date
            dialogs[dIdx].messages[idx] = m
            save()
        }
    }
    
    func removeLastUserMessage() {
        guard let id = currentDialogId, let dIdx = dialogs.firstIndex(where: { $0.id == id }) else { return }
        if let idx = dialogs[dIdx].messages.lastIndex(where: { $0.role == .user }) {
            dialogs[dIdx].messages.remove(at: idx)
            save()
        }
    }
    
    func removeLastErrorMessage() {
        guard let id = currentDialogId, let dIdx = dialogs.firstIndex(where: { $0.id == id }) else { return }
        // Удаляем все сообщения об ошибках подряд
        while let idx = dialogs[dIdx].messages.lastIndex(where: { $0.role == .assistant && $0.text == "Что-то со связью... Повтори пожалуйста" }) {
            dialogs[dIdx].messages.remove(at: idx)
        }
        save()
    }
    
    func replaceLastErrorMessageWithTyping() {
        guard let id = currentDialogId, let dIdx = dialogs.firstIndex(where: { $0.id == id }) else { return }
        if let idx = dialogs[dIdx].messages.lastIndex(where: { $0.role == .assistant && $0.text == "Что-то со связью... Повтори пожалуйста" }) {
            // Заменяем сообщение об ошибке на "Печатает..."
            let oldMessage = dialogs[dIdx].messages[idx]
            let newMessage = ChatMessage(id: oldMessage.id, role: oldMessage.role, text: "Печатает...", createdAt: oldMessage.createdAt, attachments: oldMessage.attachments, readAt: oldMessage.readAt)
            dialogs[dIdx].messages[idx] = newMessage
            save()
        }
    }
    
    func replaceLastTypingWithError() {
        guard let id = currentDialogId, let dIdx = dialogs.firstIndex(where: { $0.id == id }) else { return }
        if let idx = dialogs[dIdx].messages.lastIndex(where: { $0.role == .assistant && $0.text == "Печатает..." }) {
            // Заменяем "Печатает..." на ошибку
            let oldMessage = dialogs[dIdx].messages[idx]
            let newMessage = ChatMessage(id: oldMessage.id, role: oldMessage.role, text: "Что-то со связью... Повтори пожалуйста", createdAt: oldMessage.createdAt, attachments: oldMessage.attachments, readAt: oldMessage.readAt)
            dialogs[dIdx].messages[idx] = newMessage
            save()
        }
    }
    
    func removeLastTypingMessage() {
        guard let id = currentDialogId, let dIdx = dialogs.firstIndex(where: { $0.id == id }) else { return }
        // Удаляем все сообщения "Печатает..." подряд
        while let idx = dialogs[dIdx].messages.lastIndex(where: { $0.role == .assistant && $0.text == "Печатает..." }) {
            dialogs[dIdx].messages.remove(at: idx)
        }
        save()
    }
    
    func replaceLastTypingWithStreaming(assistantId: UUID) {
        guard let id = currentDialogId, let dIdx = dialogs.firstIndex(where: { $0.id == id }) else { return }
        if let idx = dialogs[dIdx].messages.lastIndex(where: { $0.role == .assistant && $0.text == "Печатает..." }) {
            // Заменяем "Печатает..." на пустое сообщение для стриминга
            let oldMessage = dialogs[dIdx].messages[idx]
            let newMessage = ChatMessage(id: assistantId, role: oldMessage.role, text: "", createdAt: oldMessage.createdAt, attachments: oldMessage.attachments, readAt: oldMessage.readAt)
            dialogs[dIdx].messages[idx] = newMessage
            save()
        }
    }
    
    func replaceLastErrorWithStreaming(assistantId: UUID) {
        guard let id = currentDialogId, let dIdx = dialogs.firstIndex(where: { $0.id == id }) else { return }
        if let idx = dialogs[dIdx].messages.lastIndex(where: { $0.role == .assistant && $0.text == "Что-то со связью... Повтори пожалуйста" }) {
            // Заменяем ошибку на пустое сообщение для стриминга
            let oldMessage = dialogs[dIdx].messages[idx]
            let newMessage = ChatMessage(id: assistantId, role: oldMessage.role, text: "", createdAt: oldMessage.createdAt, attachments: oldMessage.attachments, readAt: oldMessage.readAt)
            dialogs[dIdx].messages[idx] = newMessage
            save()
        }
    }
    
    func updateLastUserMessage(_ newText: String) {
        guard let id = currentDialogId, let dIdx = dialogs.firstIndex(where: { $0.id == id }) else { return }
        if let idx = dialogs[dIdx].messages.lastIndex(where: { $0.role == .user }) {
            let oldMessage = dialogs[dIdx].messages[idx]
            let newMessage = ChatMessage(id: oldMessage.id, role: oldMessage.role, text: newText, createdAt: oldMessage.createdAt, attachments: oldMessage.attachments, readAt: oldMessage.readAt)
            dialogs[dIdx].messages[idx] = newMessage
            save()
        }
    }

    func updateLastSeen(_ date: Date = Date()) {
        guard let id = currentDialogId, let dIdx = dialogs.firstIndex(where: { $0.id == id }) else { return }
        dialogs[dIdx].lastSeen = date
        save()
    }

    func setAvatar(_ data: Data?) {
        guard let id = currentDialogId, let dIdx = dialogs.firstIndex(where: { $0.id == id }) else { return }
        dialogs[dIdx].avatarData = data
        save()
    }

    func lastSeenText() -> String {
        guard let id = currentDialogId, let dialog = dialogs.first(where: { $0.id == id }) else { return "" }
        let mins = Int(Date().timeIntervalSince(dialog.lastSeen) / 60)
        
        // Рандомный статус онлайн для имитации живой девушки
        if mins <= 0 { 
            let onlineStatuses = ["В сети","В сети"]
            return onlineStatuses.randomElement() ?? "В сети"
        }
        
        // Правильные склонения для оффлайн статусов
        let minuteWord = mins == 1 ? "минуту" : (mins >= 2 && mins <= 4 ? "минуты" : "минут")
        let offlineStatuses = [
            "Был(а) в сети \(mins) \(minuteWord) назад"
        ]
        return offlineStatuses.randomElement() ?? "Был(а) в сети \(mins) \(minuteWord) назад"
    }

    func renameCurrent(to title: String) {
        guard let id = currentDialogId, let idx = dialogs.firstIndex(where: { $0.id == id }) else { return }
        dialogs[idx].title = title
        dialogs[idx].updatedAt = Date()
        save()
    }

    func delete(at offsets: IndexSet) {
        dialogs.remove(atOffsets: offsets)
        if dialogs.isEmpty { currentDialogId = nil } else if !dialogs.contains(where: { $0.id == currentDialogId }) { currentDialogId = dialogs.first?.id }
        save()
    }


    private func save() {
        do {
            let data = try JSONEncoder().encode(dialogs)
            try data.write(to: storageURL)
        } catch { }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { dialogs = []; return }
        do {
            let data = try Data(contentsOf: storageURL)
            dialogs = try JSONDecoder().decode([ChatDialog].self, from: data)
        } catch { dialogs = [] }
    }
}


